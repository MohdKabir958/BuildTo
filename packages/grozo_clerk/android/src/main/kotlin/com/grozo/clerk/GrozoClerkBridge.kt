package com.grozo.clerk

import android.app.Activity
import android.content.Intent
import com.clerk.api.Clerk
import com.clerk.api.auth.types.VerificationType
import com.clerk.api.network.model.error.ClerkErrorResponse
import com.clerk.api.signin.SignIn
import com.clerk.api.signin.attemptFirstFactor
import com.clerk.api.signup.SignUp
import com.clerk.api.signup.sendEmailCode
import com.clerk.api.signup.sendPhoneCode
import com.clerk.api.signup.verifyCode
import com.clerk.api.sso.OAuthProvider
import com.clerk.api.network.serialization.ClerkResult
import com.clerk.api.session.GetTokenOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

class GrozoClerkBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val scope = CoroutineScope(SupervisorJob()+Dispatchers.Main.immediate)
    private val methods = MethodChannel(messenger,"in.grozo/clerk")
    private val events = EventChannel(messenger,"in.grozo/clerk/events")
    private var listener: EventChannel.EventSink? = null
    private var collector: Job? = null
    private var pending: MethodChannel.Result? = null
    private var customerAuthBusy = false
    private val authRequest = 41623
    init { methods.setMethodCallHandler(this); events.setStreamHandler(this) }

    private fun snapshot(): Map<String,Any?> = mapOf(
        "ready" to Clerk.isInitialized.value,
        "signedIn" to (Clerk.isAuthFlowComplete && Clerk.session != null),
        "userId" to Clerk.user?.id, "sessionId" to Clerk.session?.id,
        "name" to listOfNotNull(Clerk.user?.firstName,Clerk.user?.lastName).joinToString(" "),
        "email" to Clerk.user?.primaryEmailAddress?.emailAddress,
    )
    private suspend fun ready() {
        GrozoClerkRuntime.configure(activity)
        check(GrozoClerkRuntime.isConfigured())
        withTimeout(20_000) { Clerk.isInitialized.first { it } }
    }
    private fun collectState() {
        if (!GrozoClerkRuntime.isConfigured() || listener == null) return
        collector?.cancel()
        collector = scope.launch {
            combine(Clerk.isInitialized,Clerk.sessionFlow,Clerk.isAuthFlowCompleteFlow) { _,_,_ -> snapshot() }
                .collect { listener?.success(it) }
        }
    }
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { listener=sink; collectState() }
    override fun onCancel(arguments: Any?) { collector?.cancel();collector=null;listener=null }

    override fun onMethodCall(call: MethodCall,result: MethodChannel.Result) {
        scope.launch {
            try {
                if (call.method == "signOut") {
                    if (customerAuthBusy) {
                        result.error("AUTH_BUSY", "Wait for sign-in to finish before signing out.", null)
                        return@launch
                    }
                    var remote = false
                    try { ready(); remote = withTimeout(15_000) { Clerk.auth.signOut() } is ClerkResult.Success }
                    catch (_: TimeoutCancellationException) { /* local removal still required */ }
                    catch (cancel: CancellationException) { throw cancel }
                    catch (_: Exception) { /* no false claim of provider revocation */ }
                    collector?.cancel()
                    GrozoClerkRuntime.clearLocal(activity)
                    collectState()
                    result.success(mapOf("localCleared" to true,"remoteRevoked" to remote))
                    return@launch
                }
                ready(); collectState()
                when(call.method) {
                    "initialize", "session" -> result.success(snapshot())
                    "authenticate" -> {
                        if (pending != null || customerAuthBusy) {result.error("AUTH_BUSY","A sign-in is already open.",null);return@launch}
                        pending=result
                        activity.startActivityForResult(Intent(activity,GrozoClerkAuthActivity::class.java).putExtra("mode",call.argument<String>("mode")?:"signInOrUp"),authRequest)
                    }
                    "customerAuth" -> {
                        if (pending != null || customerAuthBusy) {
                            result.error("AUTH_BUSY", "A sign-in is already open.", null)
                            return@launch
                        }
                        customerAuthBusy = true
                        try {
                            result.success(withTimeout(180_000) { customerAuth(call) })
                        } catch (error: CustomerAuthFailure) {
                            result.error("AUTH_FAILED", error.message, null)
                        } finally {
                            customerAuthBusy = false
                        }
                    }
                    "getToken" -> {
                        if (!Clerk.isAuthFlowComplete || Clerk.session == null) { result.success(null);return@launch }
                        when(val response = withTimeout(20_000) { Clerk.auth.getToken(GetTokenOptions(skipCache=call.argument<Boolean>("forceRefresh")==true)) }) {
                            is ClerkResult.Success -> result.success(response.value)
                            is ClerkResult.Failure -> result.error("TOKEN_UNAVAILABLE","Could not renew the session. Check your connection.",null)
                        }
                    }
                    "setActiveSession" -> {
                        val id=call.argument<String>("sessionId") ?: ""
                        // Only SDK-held active sessions are switchable; no user-provided token import.
                        check(Clerk.sessionsFlow.value.any { it.id==id && it.status.name=="ACTIVE" })
                        when(val response=withTimeout(20_000) {Clerk.auth.setActive(id)}) {
                            is ClerkResult.Success -> result.success(snapshot())
                            is ClerkResult.Failure -> result.error("SESSION_SWITCH_FAILED","Could not switch account.",null)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (_: TimeoutCancellationException) { result.error("CLERK_TIMEOUT","Secure sign-in timed out. Check your connection and retry.",null) }
            catch(cancel: CancellationException) {throw cancel}
            catch (_: Exception) { pending=null;result.error("CLERK_UNAVAILABLE","Secure sign-in is unavailable or not configured. Contact Splyzo support.",null) }
        }
    }
    private class CustomerAuthFailure(message: String) : Exception(message)

    private fun <T : Any> ClerkResult<T, ClerkErrorResponse>.requireSuccess(message: String): T =
        when (this) {
            is ClerkResult.Success -> value
            is ClerkResult.Failure -> throw CustomerAuthFailure(message)
        }

    private suspend fun completeCustomerAuth(sessionId: String?): Map<String, Any?> {
        if (sessionId == null) return mapOf("step" to "continue")
        if (Clerk.session?.id != sessionId) {
            Clerk.auth.setActive(sessionId)
                .requireSuccess("Your session could not be opened. Please try again.")
        }
        return if (Clerk.isAuthFlowComplete && Clerk.session?.id == sessionId) {
            mapOf("step" to "complete", "identity" to snapshot())
        } else {
            mapOf("step" to "continue")
        }
    }

    private suspend fun customerSignUpStep(signUp: SignUp): Map<String, Any?> =
        when {
            signUp.status == SignUp.Status.COMPLETE -> completeCustomerAuth(signUp.createdSessionId)
            signUp.missingFields.isNotEmpty() -> mapOf("step" to "continue")
            "email_address" in signUp.unverifiedFields -> mapOf("step" to "sendEmail", "attempt" to signUp.id)
            "phone_number" in signUp.unverifiedFields -> mapOf("step" to "sendPhone", "attempt" to signUp.id)
            else -> mapOf("step" to "continue")
        }

    private suspend fun customerAuth(call: MethodCall): Map<String, Any?> {
        fun value(key: String): String = call.argument<String>(key).orEmpty()
        val attempt = value("attempt")
        return when (value("action")) {
            "password" -> {
                val signIn = Clerk.auth.signInWithPassword {
                    identifier = value("identifier")
                    password = value("password")
                }.requireSuccess("Sign-in failed. Check your mobile number or email and password.")
                completeCustomerAuth(signIn.createdSessionId)
            }
            "sendOtp" -> {
                if (!Clerk.isPhoneNumberEnabled) {
                    throw CustomerAuthFailure("Mobile OTP is unavailable. Sign in with your email and password.")
                }
                val signIn = Clerk.auth.signInWithOtp { phone = value("phone") }
                    .requireSuccess("We couldn’t send a code. Check your registered mobile number and try again.")
                if (signIn.status == SignIn.Status.NEEDS_FIRST_FACTOR) {
                    mapOf("step" to "verifyPhone", "attempt" to signIn.id)
                } else {
                    completeCustomerAuth(signIn.createdSessionId)
                }
            }
            "verifyOtp" -> {
                val signIn = Clerk.auth.currentSignIn?.takeIf { it.id == attempt }
                    ?: throw CustomerAuthFailure("This code request expired. Request a new code.")
                val verified = signIn.attemptFirstFactor(SignIn.AttemptFirstFactorParams.PhoneCode(code = value("code")))
                    .requireSuccess("The code could not be verified. Check the code and try again.")
                completeCustomerAuth(verified.createdSessionId)
            }
            "signUp" -> {
                val name = value("name").split(Regex("""\s+"""), limit = 2)
                val mobile = value("phone").ifBlank { null }
                if (mobile != null && !Clerk.isPhoneNumberEnabled) {
                    throw CustomerAuthFailure("This account can be created with email. Leave the optional mobile number blank.")
                }
                val signUp = Clerk.auth.signUp {
                    email = value("email")
                    phone = mobile
                    password = value("password")
                    firstName = name.first()
                    lastName = name.getOrNull(1)
                    if (Clerk.termsUrl != null || Clerk.privacyPolicyUrl != null) {
                        legalAccepted = true
                    }
                }.requireSuccess("Could not create your account. Check your details and password, or sign in if you already have an account.")
                customerSignUpStep(signUp)
            }
            "sendEmail", "sendPhone", "verifyEmail", "verifyPhone" -> {
                val signUp = Clerk.auth.currentSignUp?.takeIf { it.id == attempt }
                    ?: throw CustomerAuthFailure("This registration expired. Start again.")
                when (value("action")) {
                    "sendEmail" -> {
                        signUp.sendEmailCode().requireSuccess("Could not send an email code. Try again.")
                        mapOf("step" to "verifyEmail", "attempt" to attempt)
                    }
                    "sendPhone" -> {
                        signUp.sendPhoneCode().requireSuccess("Could not send a mobile code. Try again.")
                        mapOf("step" to "verifyPhone", "attempt" to attempt)
                    }
                    else -> {
                        val type = if (value("action") == "verifyEmail") VerificationType.EMAIL else VerificationType.PHONE
                        val verified = signUp.verifyCode(value("code"), type)
                            .requireSuccess("The code could not be verified. Check the code and try again.")
                        customerSignUpStep(verified)
                    }
                }
            }
            "google", "apple" -> {
                val provider = if (value("action") == "google") OAuthProvider.GOOGLE else OAuthProvider.APPLE
                val result = Clerk.auth.signInWithOAuth(provider)
                    .requireSuccess("Social sign-in did not complete. Please try again.")
                completeCustomerAuth(result.signIn?.createdSessionId ?: result.signUp?.createdSessionId)
            }
            else -> throw CustomerAuthFailure("Unsupported authentication step.")
        }
    }

    fun onActivityResult(requestCode: Int,resultCode: Int): Boolean {
        if(requestCode!=authRequest) return false
        val response=pending; pending=null
        if(resultCode==Activity.RESULT_OK && Clerk.isAuthFlowComplete) response?.success(snapshot())
        else response?.error("AUTH_CANCELLED","Sign-in was cancelled.",null)
        return true
    }
    fun detach() {
        pending?.error("AUTH_CANCELLED","Authentication activity was detached.",null);pending=null
        onCancel(null);methods.setMethodCallHandler(null);events.setStreamHandler(null);scope.cancel()
    }
}
