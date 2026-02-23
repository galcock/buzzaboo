# 🐝 Buzzaboo - Next-Gen Live Streaming Platform

A modern, feature-rich live streaming platform with AI highlights, multiview, watch parties, and integrated payments powered by Stripe.

## ✨ Features

### Core Streaming
- 🔴 **Live Streaming** - Powered by LiveKit for high-quality, low-latency streams
- 📹 **Video Calls** - One-on-one and group video calling
- 🎬 **VODs & Clips** - Save and share your best moments
- 📱 **Shorts** - TikTok-style vertical short-form content
- 📺 **Multiview** - Watch multiple streams simultaneously
- 🎉 **Watch Parties** - Watch content together with friends

### AI-Powered Features
- 🤖 **AI Highlights** - Automatic highlight generation from streams
- ✂️ **Auto Clips** - AI detects and creates clips of exciting moments
- 📝 **Title Generator** - AI-suggested titles for clips and streams
- 🛡️ **Smart Moderation** - AI-powered chat moderation

### Monetization & Subscriptions
- 💳 **Stripe Integration** - Secure payment processing
- ⭐ **Platform Subscriptions** - Buzzaboo+ ($4.99/mo) and Buzzaboo Pro ($9.99/mo)
- 👥 **Creator Subscriptions** - 3-tier subscription system for individual creators
- 🎁 **Gift Subscriptions** - Send subscriptions to other users
- 💰 **Revenue Transparency** - Clear earnings breakdown for creators
- 💸 **Low Platform Fee** - 0% year 1, only 5% thereafter (lowest in industry)

### Subscription Tiers

#### Platform Subscriptions
1. **Free** - Watch streams, basic chat, follow creators
2. **Buzzaboo+ ($4.99/mo)** - Ad-free, custom emotes, subscriber badge
3. **Buzzaboo Pro ($9.99/mo)** - All above + priority support, exclusive streams, 4K quality

#### Creator Subscriptions
1. **Tier 1 ($4.99)** - Subscriber badge, sub-only chat, custom emotes
2. **Tier 2 ($9.99)** - Tier 1 + priority chat, exclusive content
3. **Tier 3 ($24.99)** - Tier 2 + VIP status, 1-on-1 with creator, Discord role

### Interactive Features
- 💬 **Live Chat** - Real-time chat with emotes and badges
- 🎯 **Predictions** - Interactive prediction system
- 🎁 **Channel Points & Rewards** - Engagement-based rewards
- 📊 **Live Polls** - Audience participation
- 🏆 **Leaderboards** - Top contributors and supporters

### Creator Tools
- 📊 **Dashboard** - Comprehensive analytics and insights
- 💰 **Revenue Tracking** - Real-time earnings and payout history
- 👥 **Subscriber Management** - View and manage your subscribers
- ⚙️ **Stream Settings** - Quality presets, chat controls, sub-only mode
- 🛡️ **Moderation Tools** - Ban, timeout, and manage chat

## 🚀 Getting Started

### Prerequisites
- Modern web browser (Chrome, Firefox, Safari, Edge)
- Node.js 18+ (for backend server)
- Stripe account (free at [stripe.com](https://stripe.com))
- LiveKit account (optional, for actual streaming)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/buzzaboo-build.git
   cd buzzaboo-build
   ```

2. **Set up Stripe** (required for payments)
   - Follow the detailed guide in [SETUP.md](SETUP.md)
   - Get your Stripe API keys
   - Update `js/stripe-service.js` with your publishable key
   - Set up backend server with secret key

3. **Open in browser**
   ```bash
   # Serve with a local server (required for some features)
   npx serve .
   # or
   python3 -m http.server 8000
   ```

4. **Navigate to** `http://localhost:8000`

## 📁 Project Structure

```
buzzaboo-build/
├── index.html              # Homepage with featured streams
├── browse.html             # Browse/discover page
├── stream.html             # Individual stream page
├── dashboard.html          # Creator dashboard
├── profile.html            # User/creator profiles
├── subscribe.html          # Platform subscription page (NEW)
├── creator-sub.html        # Creator subscription page (NEW)
├── billing.html            # Billing & subscription management (NEW)
├── multiview.html          # Multi-stream viewer
├── shorts.html             # Short-form content
├── call.html               # Video calling
├── styles.css              # Main stylesheet
├── js/
│   ├── app.js              # Main application logic
│   ├── livekit-service.js  # LiveKit integration
│   ├── stream-components.js # Stream UI components
│   ├── call-components.js   # Video call components
│   ├── stripe-service.js    # Stripe integration (NEW)
│   └── subscription-components.js # Subscription UI (NEW)
├── css/
│   └── livekit.css         # LiveKit-specific styles
├── assets/                 # Images, icons, fonts
├── manifest.json           # PWA manifest
├── sw.js                   # Service worker
├── SETUP.md                # Detailed setup guide (NEW)
└── README.md               # This file
```

## 💳 Payment Integration

Buzzaboo uses **Stripe** for secure payment processing. Features include:

- **Checkout Sessions** - Hosted payment pages
- **Subscriptions** - Recurring billing management
- **Webhooks** - Real-time event handling
- **Payment Methods** - Multiple payment method support
- **Revenue Tracking** - Detailed earnings and payout history

See [SETUP.md](SETUP.md) for complete Stripe setup instructions.

## 🎨 Design System

Buzzaboo uses a modern design system with:

- **Glassmorphism** - Frosted glass effect cards
- **Gradients** - Purple (#8B5CF6) to pink (#EC4899)
- **Dark Theme** - Default dark mode with light theme option
- **Responsive** - Mobile-first, works on all devices
- **Accessible** - WCAG 2.1 AA compliant
- **Smooth Animations** - Buttery 60fps transitions

### Color Palette
- Primary: `#8B5CF6` (Purple)
- Secondary: `#EC4899` (Pink)
- Accent: `#06B6D4` (Cyan)
- Success: `#10B981` (Green)
- Warning: `#F59E0B` (Yellow)
- Error: `#EF4444` (Red)

## 🧪 Testing Payments

Use Stripe test cards:

| Card Number | Result |
|------------|--------|
| `4242 4242 4242 4242` | Successful payment |
| `4000 0025 0000 3155` | 3D Secure required |
| `4000 0000 0000 9995` | Declined |

**Details:**
- Expiry: Any future date (e.g., 12/34)
- CVC: Any 3 digits
- ZIP: Any 5 digits

Full list: [https://stripe.com/docs/testing](https://stripe.com/docs/testing)

## 🚀 Deployment

### Frontend (Static)
Deploy to any static host:
- **Netlify** - Drag & drop deploy
- **Vercel** - Connect GitHub repo
- **GitHub Pages** - Free hosting
- **Cloudflare Pages** - Global CDN

### Backend (Node.js)
Deploy your Stripe server to:
- **Heroku** - Easy Node.js hosting
- **Railway** - Modern deployment
- **Render** - Free tier available
- **DigitalOcean** - App Platform

Remember to:
1. Set environment variables
2. Update API URLs in frontend
3. Configure webhook endpoints
4. Switch to live Stripe keys

## 🔒 Security

- ✅ Stripe handles all payment data (PCI compliant)
- ✅ Webhook signature verification
- ✅ HTTPS required in production
- ✅ No sensitive data in frontend code
- ✅ Environment variables for secrets
- ✅ Rate limiting on payment endpoints

## 🛠️ Tech Stack

- **Frontend**: HTML5, CSS3, Vanilla JavaScript
- **Payments**: Stripe Checkout & Subscriptions
- **Streaming**: LiveKit (WebRTC)
- **Design**: Custom design system with CSS variables
- **Icons**: Unicode emojis + SVG
- **Fonts**: Inter (Google Fonts)

## 📊 Browser Support

- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+
- Mobile browsers (iOS Safari, Chrome Mobile)

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License.

## 🙏 Acknowledgments

- [Stripe](https://stripe.com) - Payment processing
- [LiveKit](https://livekit.io) - WebRTC infrastructure
- [Inter Font](https://rsms.me/inter/) - Typography
- Design inspiration: Kick, Twitch, YouTube

## 📞 Support

- Documentation: [SETUP.md](SETUP.md)
- Stripe Support: [support.stripe.com](https://support.stripe.com)
- Issues: Open a GitHub issue

---

**Built with 💜 for the streaming community**

🐝 **Buzzaboo** - The future of live streaming is here.
