/* ============================================
   BUZZABOO - Stripe Payment Integration
   Handles all Stripe payment and subscription operations
   ============================================ */

// Stripe Configuration
const STRIPE_CONFIG = {
  publishableKey: "pk_test_YOUR_PUBLISHABLE_KEY_HERE",
  // Note: Secret key must be stored securely on backend
  apiVersion: "2023-10-16"
};

// Initialize Stripe (will be loaded from CDN)
let stripe = null;
let elements = null;

// Subscription Tiers
const SUBSCRIPTION_TIERS = {
  FREE: {
    id: 'free',
    name: 'Free',
    price: 0,
    currency: 'usd',
    interval: 'month',
    features: [
      'Watch live streams',
      'Basic chat features',
      'Follow favorite streamers',
      'Standard video quality'
    ]
  },
  BUZZABOO_PLUS: {
    id: 'buzzaboo_plus',
    name: 'Buzzaboo+',
    price: 4.99,
    priceId: 'price_buzzaboo_plus', // Replace with actual Stripe Price ID
    currency: 'usd',
    interval: 'month',
    features: [
      'Ad-free viewing experience',
      'Custom chat emotes',
      'Special subscriber badge',
      'Support the platform',
      'Early access to new features'
    ]
  },
  BUZZABOO_PRO: {
    id: 'buzzaboo_pro',
    name: 'Buzzaboo Pro',
    price: 9.99,
    priceId: 'price_buzzaboo_pro', // Replace with actual Stripe Price ID
    currency: 'usd',
    interval: 'month',
    features: [
      'Everything in Buzzaboo+',
      'Priority customer support',
      'Access to exclusive Pro-only streams',
      'Exclusive Pro badge',
      'Advanced video quality (4K)',
      'Download VODs for offline viewing',
      'Custom profile themes'
    ]
  }
};

// Creator Subscription Tiers
const CREATOR_SUB_TIERS = {
  TIER_1: {
    id: 'tier_1',
    name: 'Tier 1',
    defaultPrice: 4.99,
    minPrice: 2.99,
    maxPrice: 24.99,
    features: [
      'Subscriber badge',
      'Sub-only chat access',
      'Custom emotes',
      'Support the creator'
    ]
  },
  TIER_2: {
    id: 'tier_2',
    name: 'Tier 2',
    defaultPrice: 9.99,
    minPrice: 5.99,
    maxPrice: 49.99,
    features: [
      'Everything in Tier 1',
      'Special Tier 2 badge',
      'Exclusive Tier 2 emotes',
      'Priority in chat',
      'Behind-the-scenes content'
    ]
  },
  TIER_3: {
    id: 'tier_3',
    name: 'Tier 3',
    defaultPrice: 24.99,
    minPrice: 14.99,
    maxPrice: 99.99,
    features: [
      'Everything in Tier 1 & 2',
      'Elite Tier 3 badge',
      'Exclusive Tier 3 emotes',
      'VIP chat status',
      'Monthly 1-on-1 with creator',
      'Discord role & access',
      'Shoutout during stream'
    ]
  }
};

// ============================================
// STRIPE SERVICE CLASS
// ============================================

class StripeService {
  constructor() {
    this.initialized = false;
    this.currentUser = null;
    this.paymentMethods = [];
    this.subscriptions = [];
  }

  /**
   * Initialize Stripe
   */
  async init() {
    if (this.initialized) return;

    try {
      // Load Stripe.js
      if (typeof Stripe === 'undefined') {
        await this.loadStripeScript();
      }

      stripe = Stripe(STRIPE_CONFIG.publishableKey);
      this.initialized = true;
      console.log('✓ Stripe initialized');
    } catch (error) {
      console.error('Failed to initialize Stripe:', error);
      throw error;
    }
  }

  /**
   * Load Stripe.js from CDN
   */
  async loadStripeScript() {
    return new Promise((resolve, reject) => {
      if (document.querySelector('script[src*="stripe.com"]')) {
        resolve();
        return;
      }

      const script = document.createElement('script');
      script.src = 'https://js.stripe.com/v3/';
      script.async = true;
      script.onload = resolve;
      script.onerror = reject;
      document.head.appendChild(script);
    });
  }

  /**
   * Create payment element
   */
  async createPaymentElement(elementId, options = {}) {
    if (!this.initialized) await this.init();

    const appearance = {
      theme: 'night',
      variables: {
        colorPrimary: '#8B5CF6',
        colorBackground: '#1a1a1a',
        colorText: '#ffffff',
        colorDanger: '#EF4444',
        fontFamily: 'Inter, system-ui, sans-serif',
        borderRadius: '10px',
        ...options.variables
      }
    };

    elements = stripe.elements({ appearance, ...options });
    
    const paymentElement = elements.create('payment', {
      layout: 'tabs'
    });

    paymentElement.mount(elementId);
    return paymentElement;
  }

  /**
   * Create platform subscription (Buzzaboo+ or Pro)
   */
  async subscribeToPlatform(tierId) {
    if (!this.initialized) await this.init();

    const tier = SUBSCRIPTION_TIERS[tierId];
    if (!tier || tier.id === 'free') {
      throw new Error('Invalid subscription tier');
    }

    try {
      // In production, call your backend to create subscription
      const response = await this.createCheckoutSession({
        priceId: tier.priceId,
        successUrl: `${window.location.origin}/subscribe.html?success=true`,
        cancelUrl: `${window.location.origin}/subscribe.html?canceled=true`,
        mode: 'subscription'
      });

      // Redirect to Stripe Checkout
      const { error } = await stripe.redirectToCheckout({
        sessionId: response.sessionId
      });

      if (error) {
        throw error;
      }
    } catch (error) {
      console.error('Subscription failed:', error);
      throw error;
    }
  }

  /**
   * Subscribe to a creator
   */
  async subscribeToCreator(creatorId, tier, giftToUserId = null) {
    if (!this.initialized) await this.init();

    const creatorTier = CREATOR_SUB_TIERS[tier];
    if (!creatorTier) {
      throw new Error('Invalid creator subscription tier');
    }

    try {
      // In production, call your backend
      const response = await this.createCheckoutSession({
        mode: 'subscription',
        metadata: {
          type: 'creator_subscription',
          creatorId,
          tier,
          giftTo: giftToUserId
        },
        successUrl: `${window.location.origin}/creator-sub.html?creator=${creatorId}&success=true`,
        cancelUrl: `${window.location.origin}/creator-sub.html?creator=${creatorId}&canceled=true`
      });

      const { error } = await stripe.redirectToCheckout({
        sessionId: response.sessionId
      });

      if (error) {
        throw error;
      }
    } catch (error) {
      console.error('Creator subscription failed:', error);
      throw error;
    }
  }

  /**
   * Gift a subscription
   */
  async giftSubscription(creatorId, recipientUsername, tier, months = 1) {
    return this.subscribeToCreator(creatorId, tier, recipientUsername);
  }

  /**
   * Cancel subscription
   */
  async cancelSubscription(subscriptionId) {
    try {
      // In production, call your backend
      const response = await fetch('/api/subscriptions/cancel', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ subscriptionId })
      });

      if (!response.ok) throw new Error('Failed to cancel subscription');

      const data = await response.json();
      return data;
    } catch (error) {
      console.error('Cancellation failed:', error);
      throw error;
    }
  }

  /**
   * Update payment method
   */
  async updatePaymentMethod(paymentMethodId) {
    try {
      // In production, call your backend
      const response = await fetch('/api/payment-methods/update', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ paymentMethodId })
      });

      if (!response.ok) throw new Error('Failed to update payment method');

      const data = await response.json();
      return data;
    } catch (error) {
      console.error('Payment method update failed:', error);
      throw error;
    }
  }

  /**
   * Get user subscriptions
   */
  async getSubscriptions() {
    try {
      // In production, call your backend
      // For now, return mock data
      return [
        {
          id: 'sub_platform_001',
          type: 'platform',
          tier: 'BUZZABOO_PRO',
          status: 'active',
          currentPeriodEnd: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
          cancelAtPeriodEnd: false,
          price: 9.99
        },
        {
          id: 'sub_creator_001',
          type: 'creator',
          creatorId: 1,
          creatorName: 'NinjaVortex',
          tier: 'TIER_2',
          status: 'active',
          currentPeriodEnd: new Date(Date.now() + 25 * 24 * 60 * 60 * 1000),
          cancelAtPeriodEnd: false,
          price: 9.99
        }
      ];
    } catch (error) {
      console.error('Failed to fetch subscriptions:', error);
      return [];
    }
  }

  /**
   * Get payment history
   */
  async getPaymentHistory() {
    try {
      // In production, call your backend
      // For now, return mock data
      return [
        {
          id: 'inv_001',
          date: new Date(Date.now() - 5 * 24 * 60 * 60 * 1000),
          description: 'Buzzaboo Pro - Monthly',
          amount: 9.99,
          status: 'paid',
          invoiceUrl: '#'
        },
        {
          id: 'inv_002',
          date: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
          description: 'NinjaVortex Tier 2 Subscription',
          amount: 9.99,
          status: 'paid',
          invoiceUrl: '#'
        },
        {
          id: 'inv_003',
          date: new Date(Date.now() - 35 * 24 * 60 * 60 * 1000),
          description: 'Buzzaboo Pro - Monthly',
          amount: 9.99,
          status: 'paid',
          invoiceUrl: '#'
        }
      ];
    } catch (error) {
      console.error('Failed to fetch payment history:', error);
      return [];
    }
  }

  /**
   * Get creator earnings (for dashboard)
   */
  async getCreatorEarnings() {
    try {
      // In production, call your backend
      // For now, return mock data
      return {
        total: 12450.00,
        thisMonth: 4230.00,
        breakdown: {
          subscriptions: 7230.00,
          bits: 2845.00,
          ads: 1560.00,
          sponsorships: 815.00
        },
        subscribers: {
          tier1: 156,
          tier2: 42,
          tier3: 18,
          total: 216
        },
        payouts: [
          {
            id: 'po_001',
            date: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000),
            amount: 8220.00,
            status: 'paid',
            method: 'Bank Transfer'
          },
          {
            id: 'po_002',
            date: new Date(Date.now() - 60 * 24 * 60 * 60 * 1000),
            amount: 7650.00,
            status: 'paid',
            method: 'Bank Transfer'
          }
        ]
      };
    } catch (error) {
      console.error('Failed to fetch creator earnings:', error);
      return null;
    }
  }

  /**
   * Create Stripe Checkout Session (Backend API call)
   */
  async createCheckoutSession(params) {
    // In production, this would call your backend
    // Backend would use Stripe's server-side SDK
    // For demo purposes, we'll return a mock session
    console.log('Creating checkout session:', params);
    
    // This is a placeholder - in production, call:
    // const response = await fetch('/api/create-checkout-session', {
    //   method: 'POST',
    //   headers: { 'Content-Type': 'application/json' },
    //   body: JSON.stringify(params)
    // });
    // return response.json();

    return {
      sessionId: 'mock_session_' + Date.now()
    };
  }

  /**
   * Format currency
   */
  formatCurrency(amount, currency = 'USD') {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: currency
    }).format(amount);
  }

  /**
   * Format date
   */
  formatDate(date) {
    return new Intl.DateTimeFormat('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    }).format(new Date(date));
  }
}

// ============================================
// EXPORT
// ============================================

// Create singleton instance
const stripeService = new StripeService();

// Make available globally
window.StripeService = StripeService;
window.stripeService = stripeService;
window.SUBSCRIPTION_TIERS = SUBSCRIPTION_TIERS;
window.CREATOR_SUB_TIERS = CREATOR_SUB_TIERS;

console.log('✓ Stripe Service loaded');
