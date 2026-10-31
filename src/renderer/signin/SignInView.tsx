import { useEffect, useState } from 'react';
import type { AuthStatus, CliAuthStatus } from '@contracts/events.js';
import { request } from '../settings/ipc.js';

const api = window.grokDictate;

export function SignInView(): React.JSX.Element {
  const [status, setStatus] = useState<AuthStatus | null>(null);
  const [cli, setCli] = useState<CliAuthStatus | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void request({ type: 'get-auth-status' }, 'auth-status').then((outcome) => {
      if (outcome.ok) setStatus(outcome.value.status);
      else setError(outcome.message);
    });
    void request({ type: 'get-cli-status' }, 'cli-status').then((outcome) => {
      if (outcome.ok) setCli(outcome.value.status);
    });
    return api.on((message) => {
      if (message.type === 'auth-updated') setStatus(message.status);
    });
  }, []);

  const signInWithGrok = (): void => {
    setBusy(true);
    setError(null);
    void request({ type: 'start-grok-cli-login' }, 'cli-status').then((outcome) => {
      setBusy(false);
      if (!outcome.ok) {
        setError(outcome.message);
        return;
      }
      setCli(outcome.value.status);
      void request({ type: 'get-auth-status' }, 'auth-status').then((auth) => {
        if (auth.ok) setStatus(auth.value.status);
      });
    });
  };

  const signedIn = status?.state === 'signed-in';

  return (
    <main className="panel signin">
      <header className="panel-head">
        <h1>Sign in</h1>
      </header>
      <div className="panel-body">
        <p className="signin-lead">
          Sign in with your Grok account. The xAI API path uses the Grok CLI login. grok.com is a
          separate login for STT 2 Fast, under Settings → Account.
        </p>

        {error !== null ? (
          <div className="issues" role="alert">
            <p>{error}</p>
          </div>
        ) : null}

        {signedIn ? (
          <p className="signin-lead">
            You can close this window and hold the right Command key to dictate.
          </p>
        ) : (
          <div className="actions">
            <button type="button" className="primary" disabled={busy} onClick={signInWithGrok}>
              {busy ? 'Waiting for Terminal…' : 'Sign in with Grok'}
            </button>
            <button
              type="button"
              onClick={() => {
                api.send({ type: 'open-window', window: 'grok-com-signin' });
              }}
            >
              Sign in to grok.com…
            </button>
          </div>
        )}

        {cli?.state === 'expired' ? (
          <p className="signin-status warn" role="status">
            The Grok CLI login is expired. Sign in again, or refresh it in Settings → Account.
          </p>
        ) : null}
      </div>
    </main>
  );
}
