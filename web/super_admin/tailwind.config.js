import brand from '../../branding/brand.json' with { type: 'json' };
/** @type {import('tailwindcss').Config} */
// Splyzo design tokens. Hex values mirror packages/kraveo_ui (KraveoPalette / KStatus / KraveoTokens.driver).
// Keep in sync with src/lib/tokens.ts (used where a raw hex is required, e.g. Recharts).
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        kraveo: {
          // Splyzo navy and blue ramp (brand = g800)
          g50: '#EFF5FF',
          g100: '#DCE9FF',
          g200: '#B8D2FF',
          g300: '#82B5F9',
          g400: '#4A8EDC', // dark-surface brand (driver/admin)
          g500: '#216BC2',
          g600: '#1555A6',
          g700: '#103F83',
          g800: brand.primary,
          g900: '#082451',
          g950: '#041633',
          brand: brand.primary,
          brandSoft: '#EFF5FF',
          // Splyzo orange accent (brand = 400)
          yellow: brand.accent,
          y100: '#FFF1E8',
          y200: '#FFD7C2',
          y300: '#FFB38A',
          y400: brand.accent,
          y500: '#DD4719',
          y700: '#9B2E12',
          // Cream (used only on the logo badge)
          cream: '#F5F8FC',
          // Night (driver / admin) neutrals
          night: '#F5F8FC',
          surface: '#FFFFFF',
          surface2: '#EDF2F8',
          line: '#DCE5F0',
          ink: '#14243B',
          ink2: '#46566F',
          ink3: '#64748B',
          // Semantic
          success: '#176B37',
          warning: '#865000',
          danger: '#B42332',
          info: '#245CA2',
          // One status language across every Splyzo surface
          status: {
            placed: '#875500',
            accepted: '#0A655C',
            preparing: '#A44713',
            ready: '#3C6611',
            pickedUp: '#245CA2',
            atGate: '#6745A3',
            delivered: '#176B37',
            cancelled: '#E5484D',
          },
        },
      },
      fontFamily: {
        sans: ['"Plus Jakarta Sans Variable"', '"Plus Jakarta Sans"', 'system-ui', 'sans-serif'],
        display: ['"Bricolage Grotesque Variable"', '"Bricolage Grotesque"', '"Plus Jakarta Sans Variable"', 'system-ui', 'sans-serif'],
      },
      borderRadius: {
        'k-sm': '8px',
        'k-md': '12px',
        'k-lg': '12px',
        'k-xl': '16px',
        'k-2xl': '24px',
      },
      boxShadow: {
        // KShadow.soft / lift / glow. Dark surfaces need a stronger alpha than the light apps to stay visible.
        'k-soft': '0 1px 3px rgba(20,36,59,0.03)',
        'k-lift': '0 8px 24px rgba(20,36,59,0.08)',
        'k-glow': '0 1px 3px rgba(20,36,59,0.05)',
        'k-glow-yellow': '0 1px 3px rgba(20,36,59,0.05)',
      },
      transitionDuration: {
        fast: '140ms',
        base: '260ms',
        slow: '480ms',
      },
      transitionTimingFunction: {
        emphasized: 'cubic-bezier(0.215, 0.61, 0.355, 1)', // easeOutCubic
        spring: 'cubic-bezier(0.175, 0.885, 0.32, 1.275)', // easeOutBack
      },
      keyframes: {
        'fade-up': {
          '0%': { opacity: '0', transform: 'translateY(10px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        'fade-in': {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        'scale-in': {
          '0%': { opacity: '0', transform: 'scale(0.96)' },
          '100%': { opacity: '1', transform: 'scale(1)' },
        },
        'slide-in-right': {
          '0%': { transform: 'translateX(100%)' },
          '100%': { transform: 'translateX(0)' },
        },
        'slide-in-left': {
          '0%': { transform: 'translateX(-100%)' },
          '100%': { transform: 'translateX(0)' },
        },
        'slide-up': {
          '0%': { transform: 'translateY(100%)' },
          '100%': { transform: 'translateY(0)' },
        },
        shimmer: {
          '0%': { backgroundPosition: '150% 0' },
          '100%': { backgroundPosition: '-50% 0' },
        },
        'dot-pulse': {
          '0%': { boxShadow: '0 0 0 0 var(--dot, rgba(74,142,220,0.55))' },
          '70%': { boxShadow: '0 0 0 7px transparent' },
          '100%': { boxShadow: '0 0 0 0 transparent' },
        },
        'ring-out': {
          '0%': { transform: 'scale(0.6)', opacity: '0.7' },
          '100%': { transform: 'scale(2.4)', opacity: '0' },
        },
        'toast-in': {
          '0%': { opacity: '0', transform: 'translateY(12px) scale(0.98)' },
          '100%': { opacity: '1', transform: 'translateY(0) scale(1)' },
        },
      },
      animation: {
        'fade-up': 'fade-up 480ms cubic-bezier(0.215, 0.61, 0.355, 1) both',
        'fade-in': 'fade-in 260ms ease-out both',
        'scale-in': 'scale-in 260ms cubic-bezier(0.175, 0.885, 0.32, 1.275) both',
        'slide-in-right': 'slide-in-right 320ms cubic-bezier(0.215, 0.61, 0.355, 1) both',
        'slide-in-left': 'slide-in-left 280ms cubic-bezier(0.215, 0.61, 0.355, 1) both',
        'slide-up': 'slide-up 320ms cubic-bezier(0.215, 0.61, 0.355, 1) both',
        shimmer: 'shimmer 1.4s linear infinite',
        'dot-pulse': 'dot-pulse 1.6s ease-out infinite',
        'ring-out': 'ring-out 2s ease-out infinite',
        'toast-in': 'toast-in 320ms cubic-bezier(0.175, 0.885, 0.32, 1.275) both',
      },
    },
  },
  plugins: [],
}
