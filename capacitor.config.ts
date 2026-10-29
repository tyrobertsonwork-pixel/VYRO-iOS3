import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'app.vyro.cinema',
  appName: 'VYRO',
  webDir: 'www',
  plugins: {
    // Use native iOS networking for provider APIs so WKWebView CORS
    // restrictions do not block Xtream requests in the installed app.
    CapacitorHttp: { enabled: true }
  },
  ios: { contentInset: 'automatic', backgroundColor: '#080811' }
};

export default config;
