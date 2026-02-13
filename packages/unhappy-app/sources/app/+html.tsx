import { ScrollViewStyleReset } from 'expo-router/html';
import '../unistyles';

// This file is web-only and used to configure the root HTML for every
// web page during static rendering.
// The contents of this function only run in Node.js environments and
// do not have access to the DOM or browser APIs.
export default function Root({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <meta charSet="utf-8" />
        <meta httpEquiv="X-UA-Compatible" content="IE=edge" />
        <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no" />
        <meta name="theme-color" content="#18171C" />
        <meta name="mobile-web-app-capable" content="yes" />
        <meta name="apple-mobile-web-app-capable" content="yes" />
        <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
        <meta name="apple-mobile-web-app-title" content="Unhappy" />
        <link rel="icon" href="./favicon.ico" />
        <link rel="apple-touch-icon" href="./apple-touch-icon.png" />
        <link rel="manifest" href="./manifest.webmanifest" />

        {/* 
          Disable body scrolling on web. This makes ScrollView components work closer to how they do on native. 
          However, body scrolling is often nice to have for mobile web. If you want to enable it, remove this line.
        */}
        <ScrollViewStyleReset />

        {/* Using raw CSS styles as an escape-hatch to ensure the background color never flickers in dark-mode. */}
        <style dangerouslySetInnerHTML={{ __html: responsiveBackground }} />
        {/* Add any additional <head> elements that you want globally available on web... */}
      </head>
      <body>
        {children}
        <script dangerouslySetInnerHTML={{ __html: registerServiceWorkerScript }} />
      </body>
    </html>
  );
}

const responsiveBackground = `
body {
  /* Match the app's web "light" background. */
  background-color: #FFFFFF;
}
@media (prefers-color-scheme: dark) {
  body {
    /* Match the app's web "dark" background (near-black). */
    background-color: #0B0B0C;
  }
}`;

const registerServiceWorkerScript = `
(() => {
  const canRegister = 'serviceWorker' in navigator && window.isSecureContext;
  if (!canRegister) return;
  
  const hadController = Boolean(navigator.serviceWorker.controller);
  let reloadingForUpdate = false;

  const reloadOnControllerChange = () => {
    if (!hadController || reloadingForUpdate) return;
    reloadingForUpdate = true;
    window.location.reload();
  };

  navigator.serviceWorker.addEventListener('controllerchange', reloadOnControllerChange);

  const activateWaitingWorker = (registration) => {
    if (registration.waiting) {
      registration.waiting.postMessage({ type: 'SKIP_WAITING' });
    }
  };

  const attachUpdateListener = (registration) => {
    registration.addEventListener('updatefound', () => {
      const newWorker = registration.installing;
      if (!newWorker) return;

      newWorker.addEventListener('statechange', () => {
        if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
          activateWaitingWorker(registration);
        }
      });
    });
  };

  const register = async () => {
    try {
      const registration = await navigator.serviceWorker.register('./sw.js', {
        updateViaCache: 'none',
      });

      activateWaitingWorker(registration);
      attachUpdateListener(registration);

      const checkForUpdate = () => {
        registration.update().catch((error) => {
          console.warn('[PWA] Service worker update check failed', error);
        });
      };

      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') {
          checkForUpdate();
        }
      });
      window.addEventListener('focus', checkForUpdate);
      window.setInterval(checkForUpdate, 5 * 60 * 1000);
    } catch (error) {
      console.warn('[PWA] Service worker registration failed', error);
    }
  };

  window.addEventListener('load', register);
})();
`;
