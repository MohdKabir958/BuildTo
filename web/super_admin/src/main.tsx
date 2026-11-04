import { ClerkAdminRoot, clerkEnabled } from './auth/ClerkAdmin';
import React from 'react';
import ReactDOM from 'react-dom/client';
import '@fontsource-variable/bricolage-grotesque';
import '@fontsource-variable/plus-jakarta-sans';
import { App } from './App';
import { AdminShell } from './v21/AdminShell';
import { ErrorBoundary } from './components/ErrorBoundary';
import { ToastProvider } from './components/ui/Toast';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ErrorBoundary>
      <ToastProvider>
        {import.meta.env.VITE_ADMIN_VERSION === 'v21' ? <AdminShell /> : clerkEnabled ? <ClerkAdminRoot /> : <App />}
      </ToastProvider>
    </ErrorBoundary>
  </React.StrictMode>
);
