/** Shared funding proof for every financial/fulfillment workflow.
 * A failed/cancelled gateway attempt is HISTORY, never a reason to reject a
 * subsequently verified capture. Multiple captures or unreconciled active
 * attempts remain unsafe and must go to finance review.
 */
export interface PaymentEvidence {
  provider:string;
  status:string;
  amountPaise:bigint;
  capturedPaise:bigint;
  verifiedAt:Date|null;
  providerPayRef:string|null;
  paymentMethod?:string;
}

const terminal=(p:PaymentEvidence)=>p.status==='FAILED'||p.status==='CANCELLED';

export function verifiedCapturedPayment<T extends PaymentEvidence>(
  payments:readonly T[], totalPaise:bigint
):T|null {
  const captures=payments.filter(p=>p.status==='CAPTURED');
  if(captures.length!==1)return null;
  const captured=captures[0];
  if(captured.provider!=='RAZORPAY'||!captured.verifiedAt||
     !captured.providerPayRef||captured.amountPaise!==totalPaise||
     captured.capturedPaise!==totalPaise)return null;
  // Do not silently dismiss another active gateway attempt that could also
  // capture; it must be explicitly reconciled before money is disbursed.
  if(payments.some(p=>p!==captured&&!terminal(p)))return null;
  return captured;
}

export function verifiedFulfillmentPayment<T extends PaymentEvidence>(
  payments:readonly T[],totalPaise:bigint
):T|null {
  const captured=verifiedCapturedPayment(payments,totalPaise);
  if(captured)return captured;
  const active=payments.filter(p=>!terminal(p));
  if(active.length!==1)return null;
  const cod=active[0];
  if(cod.provider!=='MANUAL'||cod.paymentMethod!=='COD'||
     cod.status!=='PENDING'||cod.capturedPaise!==0n||
     cod.amountPaise!==totalPaise)return null;
  // Captured online funds and COD selection cannot coexist.
  if(payments.some(p=>p.status==='CAPTURED'))return null;
  return cod;
}
