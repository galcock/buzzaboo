/* ============================================
   BUZZABOO - Subscription UI Components
   Reusable components for subscription features
   ============================================ */

// ============================================
// SUBSCRIPTION TIER CARD
// ============================================

function createSubscriptionTierCard(tier, isCurrentPlan = false) {
  const tierData = SUBSCRIPTION_TIERS[tier];
  if (!tierData) return '';

  const isFree = tierData.id === 'free';
  const popular = tierData.id === 'buzzaboo_plus';

  return `
    <div class="subscription-tier-card ${popular ? 'popular' : ''} ${isCurrentPlan ? 'current' : ''}" data-tier="${tierData.id}">
      ${popular ? '<div class="tier-badge">Most Popular</div>' : ''}
      ${isCurrentPlan ? '<div class="tier-badge current-badge">Current Plan</div>' : ''}
      
      <div class="tier-header">
        <h3 class="tier-name">${tierData.name}</h3>
        <div class="tier-price">
          ${isFree ? 
            '<span class="price-amount">Free</span>' :
            `<span class="price-amount">$${tierData.price}</span>
             <span class="price-period">/month</span>`
          }
        </div>
      </div>

      <ul class="tier-features">
        ${tierData.features.map(feature => `
          <li class="tier-feature">
            <span class="feature-icon">✓</span>
            <span class="feature-text">${feature}</span>
          </li>
        `).join('')}
      </ul>

      ${!isCurrentPlan ? `
        <button class="btn ${popular ? 'btn-primary' : 'btn-secondary'} btn-block subscribe-btn" 
                data-tier="${tierData.id}"
                ${isFree ? 'disabled' : ''}>
          ${isFree ? 'Current Plan' : 'Subscribe Now'}
        </button>
      ` : `
        <button class="btn btn-secondary btn-block" disabled>
          Current Plan
        </button>
      `}
    </div>
  `;
}

// ============================================
// CREATOR SUBSCRIPTION CARD
// ============================================

function createCreatorSubCard(creator, tier, customPrice = null) {
  const tierData = CREATOR_SUB_TIERS[tier];
  if (!tierData) return '';

  const price = customPrice || tierData.defaultPrice;

  return `
    <div class="creator-sub-card" data-tier="${tierData.id}">
      <div class="tier-header">
        <h3 class="tier-name">${tierData.name}</h3>
        <div class="tier-price">
          <span class="price-amount">$${price.toFixed(2)}</span>
          <span class="price-period">/month</span>
        </div>
      </div>

      <ul class="tier-features">
        ${tierData.features.map(feature => `
          <li class="tier-feature">
            <span class="feature-icon">✓</span>
            <span class="feature-text">${feature}</span>
          </li>
        `).join('')}
      </ul>

      <div class="sub-actions">
        <button class="btn btn-primary btn-block creator-subscribe-btn" 
                data-creator-id="${creator.id}" 
                data-tier="${tierData.id}"
                data-price="${price}">
          Subscribe
        </button>
        <button class="btn btn-secondary btn-block creator-gift-btn"
                data-creator-id="${creator.id}" 
                data-tier="${tierData.id}"
                data-price="${price}">
          🎁 Gift Sub
        </button>
      </div>
    </div>
  `;
}

// ============================================
// SUBSCRIPTION BADGE (for chat/profile)
// ============================================

function createSubscriptionBadge(subscription, size = 'small') {
  if (!subscription) return '';

  let badgeClass = 'sub-badge';
  let badgeText = '';
  let badgeIcon = '⭐';

  if (subscription.type === 'platform') {
    if (subscription.tier === 'BUZZABOO_PLUS') {
      badgeClass += ' badge-plus';
      badgeText = '+';
      badgeIcon = '⭐';
    } else if (subscription.tier === 'BUZZABOO_PRO') {
      badgeClass += ' badge-pro';
      badgeText = 'PRO';
      badgeIcon = '💎';
    }
  } else if (subscription.type === 'creator') {
    badgeClass += ' badge-creator';
    const tierNum = subscription.tier.replace('TIER_', '');
    badgeText = `T${tierNum}`;
    badgeIcon = tierNum === '3' ? '👑' : tierNum === '2' ? '💜' : '💙';
  }

  return `
    <span class="${badgeClass} ${size}" title="${subscription.type === 'platform' ? 'Buzzaboo ' + badgeText : 'Subscriber'}" 
          data-tooltip="${subscription.type === 'platform' ? 'Buzzaboo Subscriber' : 'Creator Subscriber'}">
      ${badgeIcon}
    </span>
  `;
}

// ============================================
// GIFT SUBSCRIPTION MODAL
// ============================================

function createGiftSubModal(creator, tier, price) {
  return `
    <div class="modal" id="giftSubModal">
      <div class="modal-overlay"></div>
      <div class="modal-content">
        <div class="modal-header">
          <h2>🎁 Gift a Subscription</h2>
          <button class="modal-close">&times;</button>
        </div>

        <div class="modal-body">
          <div class="gift-preview">
            <img src="${creator.avatar}" alt="${creator.displayName}" class="gift-creator-avatar">
            <div class="gift-details">
              <h3>${creator.displayName}</h3>
              <p>${CREATOR_SUB_TIERS[tier].name} - $${price.toFixed(2)}/month</p>
            </div>
          </div>

          <div class="form-group">
            <label class="form-label">Recipient Username</label>
            <input type="text" 
                   class="form-input" 
                   id="giftRecipient" 
                   placeholder="Enter username">
            <p class="form-hint">They'll receive a notification about your gift!</p>
          </div>

          <div class="form-group">
            <label class="form-label">Number of Months</label>
            <select class="form-input form-select" id="giftMonths">
              <option value="1">1 month - $${price.toFixed(2)}</option>
              <option value="3">3 months - $${(price * 3).toFixed(2)}</option>
              <option value="6">6 months - $${(price * 6).toFixed(2)}</option>
              <option value="12">12 months - $${(price * 12).toFixed(2)}</option>
            </select>
          </div>

          <div class="form-group">
            <label class="form-checkbox">
              <input type="checkbox" id="giftAnonymous">
              <span>Send anonymously</span>
            </label>
          </div>

          <div class="form-group">
            <label class="form-label">Message (Optional)</label>
            <textarea class="form-input" 
                      id="giftMessage" 
                      rows="3" 
                      placeholder="Add a personal message..."></textarea>
          </div>
        </div>

        <div class="modal-footer">
          <button class="btn btn-secondary modal-cancel">Cancel</button>
          <button class="btn btn-primary" id="confirmGift">
            🎁 Gift Subscription
          </button>
        </div>
      </div>
    </div>
  `;
}

// ============================================
// SUBSCRIPTION MANAGEMENT CARD
// ============================================

function createSubscriptionManagementCard(subscription) {
  const isActive = subscription.status === 'active';
  const willCancel = subscription.cancelAtPeriodEnd;

  let tierName = '';
  let description = '';

  if (subscription.type === 'platform') {
    const tier = SUBSCRIPTION_TIERS[subscription.tier];
    tierName = tier.name;
    description = `Platform subscription - $${subscription.price}/month`;
  } else if (subscription.type === 'creator') {
    tierName = `${subscription.creatorName} - ${CREATOR_SUB_TIERS[subscription.tier].name}`;
    description = `Creator subscription - $${subscription.price}/month`;
  }

  return `
    <div class="subscription-card ${!isActive ? 'inactive' : ''}" data-subscription-id="${subscription.id}">
      <div class="sub-card-header">
        <div class="sub-info">
          <h3 class="sub-title">${tierName}</h3>
          <p class="sub-description">${description}</p>
        </div>
        <div class="sub-status">
          <span class="status-badge ${isActive ? 'active' : 'inactive'}">
            ${isActive ? '✓ Active' : '○ Inactive'}
          </span>
        </div>
      </div>

      <div class="sub-card-body">
        <div class="sub-detail">
          <span class="detail-label">Next billing date:</span>
          <span class="detail-value">${stripeService.formatDate(subscription.currentPeriodEnd)}</span>
        </div>
        ${willCancel ? `
          <div class="sub-detail warning">
            <span class="detail-label">⚠️ Cancels on:</span>
            <span class="detail-value">${stripeService.formatDate(subscription.currentPeriodEnd)}</span>
          </div>
        ` : ''}
      </div>

      <div class="sub-card-footer">
        ${!willCancel ? `
          <button class="btn btn-secondary btn-sm cancel-subscription" 
                  data-subscription-id="${subscription.id}">
            Cancel Subscription
          </button>
        ` : `
          <button class="btn btn-primary btn-sm reactivate-subscription" 
                  data-subscription-id="${subscription.id}">
            Reactivate Subscription
          </button>
        `}
        <button class="btn btn-secondary btn-sm">
          Update Payment Method
        </button>
      </div>
    </div>
  `;
}

// ============================================
// PAYMENT HISTORY ITEM
// ============================================

function createPaymentHistoryItem(payment) {
  const statusClass = payment.status === 'paid' ? 'success' : 
                      payment.status === 'pending' ? 'warning' : 'error';

  return `
    <div class="payment-history-item">
      <div class="payment-info">
        <div class="payment-date">${stripeService.formatDate(payment.date)}</div>
        <div class="payment-description">${payment.description}</div>
      </div>
      <div class="payment-details">
        <div class="payment-amount">${stripeService.formatCurrency(payment.amount)}</div>
        <span class="payment-status ${statusClass}">${payment.status}</span>
        ${payment.invoiceUrl ? `
          <a href="${payment.invoiceUrl}" class="btn btn-ghost btn-sm" target="_blank">
            📄 Invoice
          </a>
        ` : ''}
      </div>
    </div>
  `;
}

// ============================================
// SUB-ONLY CHAT MODE TOGGLE
// ============================================

function createSubOnlyChatToggle(isEnabled = false) {
  return `
    <div class="stream-setting">
      <div class="setting-info">
        <h4 class="setting-title">Subscribers-Only Chat</h4>
        <p class="setting-description">Only subscribers can send messages</p>
      </div>
      <label class="toggle-switch">
        <input type="checkbox" id="subOnlyChat" ${isEnabled ? 'checked' : ''}>
        <span class="toggle-slider"></span>
      </label>
    </div>
  `;
}

// ============================================
// REVENUE DISPLAY WIDGET
// ============================================

function createRevenueWidget(earnings) {
  if (!earnings) return '<div class="glass-card" style="padding: 2rem;">Loading earnings...</div>';

  return `
    <div class="glass-card revenue-widget" style="padding: 1.5rem;">
      <div class="revenue-header">
        <h2 class="section-title">💰 Your Earnings</h2>
        <button class="btn btn-secondary btn-sm" id="payoutSettings">
          Payout Settings
        </button>
      </div>

      <div class="revenue-total">
        <p class="revenue-label">Total Earnings (This Month)</p>
        <div class="revenue-amount">${stripeService.formatCurrency(earnings.thisMonth)}</div>
        <p class="revenue-sublabel">All-time: ${stripeService.formatCurrency(earnings.total)}</p>
      </div>

      <div class="revenue-breakdown">
        <div class="breakdown-item">
          <div class="breakdown-icon">⭐</div>
          <div class="breakdown-info">
            <div class="breakdown-label">Subscriptions</div>
            <div class="breakdown-value">${stripeService.formatCurrency(earnings.breakdown.subscriptions)}</div>
            <div class="breakdown-detail">${earnings.subscribers.total} subscribers</div>
          </div>
        </div>

        <div class="breakdown-item">
          <div class="breakdown-icon">💎</div>
          <div class="breakdown-info">
            <div class="breakdown-label">Bits & Tips</div>
            <div class="breakdown-value">${stripeService.formatCurrency(earnings.breakdown.bits)}</div>
          </div>
        </div>

        <div class="breakdown-item">
          <div class="breakdown-icon">🎯</div>
          <div class="breakdown-info">
            <div class="breakdown-label">Ad Revenue</div>
            <div class="breakdown-value">${stripeService.formatCurrency(earnings.breakdown.ads)}</div>
          </div>
        </div>

        <div class="breakdown-item">
          <div class="breakdown-icon">🎁</div>
          <div class="breakdown-info">
            <div class="breakdown-label">Sponsorships</div>
            <div class="breakdown-value">${stripeService.formatCurrency(earnings.breakdown.sponsorships)}</div>
          </div>
        </div>
      </div>

      <div class="revenue-subs-breakdown">
        <h4>Subscriber Breakdown</h4>
        <div class="subs-tiers">
          <div class="sub-tier-stat">
            <span class="tier-count">${earnings.subscribers.tier1}</span>
            <span class="tier-label">Tier 1</span>
          </div>
          <div class="sub-tier-stat">
            <span class="tier-count">${earnings.subscribers.tier2}</span>
            <span class="tier-label">Tier 2</span>
          </div>
          <div class="sub-tier-stat">
            <span class="tier-count">${earnings.subscribers.tier3}</span>
            <span class="tier-label">Tier 3</span>
          </div>
        </div>
      </div>

      <div class="revenue-footer">
        <p class="revenue-note">
          <span class="note-icon">✓</span>
          Buzzaboo takes 0% cut for the first year. After that, only 5% - the lowest in the industry.
        </p>
      </div>
    </div>
  `;
}

// ============================================
// PAYOUT HISTORY TABLE
// ============================================

function createPayoutHistoryTable(payouts) {
  if (!payouts || payouts.length === 0) {
    return `
      <div class="glass-card" style="padding: 2rem; text-align: center;">
        <p style="color: var(--text-secondary);">No payout history yet</p>
      </div>
    `;
  }

  return `
    <div class="glass-card" style="padding: 1.5rem;">
      <h3 class="section-title">Payout History</h3>
      <div class="payout-table">
        <table>
          <thead>
            <tr>
              <th>Date</th>
              <th>Amount</th>
              <th>Method</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            ${payouts.map(payout => `
              <tr>
                <td>${stripeService.formatDate(payout.date)}</td>
                <td class="amount">${stripeService.formatCurrency(payout.amount)}</td>
                <td>${payout.method}</td>
                <td>
                  <span class="status-badge ${payout.status}">${payout.status}</span>
                </td>
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    </div>
  `;
}

// ============================================
// EVENT HANDLERS
// ============================================

// Initialize subscription components
function initSubscriptionComponents() {
  // Subscribe button handlers
  document.addEventListener('click', async (e) => {
    if (e.target.classList.contains('subscribe-btn')) {
      const tier = e.target.dataset.tier;
      try {
        await stripeService.subscribeToPlatform(tier.toUpperCase());
      } catch (error) {
        alert('Subscription failed: ' + error.message);
      }
    }

    // Creator subscribe button
    if (e.target.classList.contains('creator-subscribe-btn')) {
      const creatorId = e.target.dataset.creatorId;
      const tier = e.target.dataset.tier;
      try {
        await stripeService.subscribeToCreator(creatorId, tier);
      } catch (error) {
        alert('Subscription failed: ' + error.message);
      }
    }

    // Gift subscription button
    if (e.target.classList.contains('creator-gift-btn')) {
      const creatorId = e.target.dataset.creatorId;
      const tier = e.target.dataset.tier;
      const price = parseFloat(e.target.dataset.price);
      
      const creator = STREAMERS.find(s => s.id == creatorId);
      if (creator) {
        showGiftSubModal(creator, tier, price);
      }
    }

    // Cancel subscription
    if (e.target.classList.contains('cancel-subscription')) {
      const subId = e.target.dataset.subscriptionId;
      if (confirm('Are you sure you want to cancel this subscription? You\'ll retain access until the end of the current billing period.')) {
        try {
          await stripeService.cancelSubscription(subId);
          alert('Subscription cancelled successfully');
          location.reload();
        } catch (error) {
          alert('Cancellation failed: ' + error.message);
        }
      }
    }
  });

  // Sub-only chat toggle
  const subOnlyToggle = document.getElementById('subOnlyChat');
  if (subOnlyToggle) {
    subOnlyToggle.addEventListener('change', (e) => {
      const enabled = e.target.checked;
      console.log('Sub-only chat:', enabled);
      // In production, save this setting to backend
    });
  }
}

// Show gift subscription modal
function showGiftSubModal(creator, tier, price) {
  const modalHTML = createGiftSubModal(creator, tier, price);
  const modalContainer = document.createElement('div');
  modalContainer.innerHTML = modalHTML;
  document.body.appendChild(modalContainer.firstElementChild);

  const modal = document.getElementById('giftSubModal');
  
  // Show modal
  setTimeout(() => modal.classList.add('active'), 10);

  // Close modal handlers
  const closeModal = () => {
    modal.classList.remove('active');
    setTimeout(() => modal.remove(), 300);
  };

  modal.querySelector('.modal-close').addEventListener('click', closeModal);
  modal.querySelector('.modal-cancel').addEventListener('click', closeModal);
  modal.querySelector('.modal-overlay').addEventListener('click', closeModal);

  // Confirm gift handler
  modal.querySelector('#confirmGift').addEventListener('click', async () => {
    const recipient = document.getElementById('giftRecipient').value;
    const months = parseInt(document.getElementById('giftMonths').value);
    
    if (!recipient) {
      alert('Please enter a recipient username');
      return;
    }

    try {
      await stripeService.giftSubscription(creator.id, recipient, tier, months);
      closeModal();
    } catch (error) {
      alert('Gift subscription failed: ' + error.message);
    }
  });
}

// ============================================
// EXPORT
// ============================================

window.SubscriptionComponents = {
  createSubscriptionTierCard,
  createCreatorSubCard,
  createSubscriptionBadge,
  createGiftSubModal,
  createSubscriptionManagementCard,
  createPaymentHistoryItem,
  createSubOnlyChatToggle,
  createRevenueWidget,
  createPayoutHistoryTable,
  initSubscriptionComponents,
  showGiftSubModal
};

// Auto-initialize
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initSubscriptionComponents);
} else {
  initSubscriptionComponents();
}

console.log('✓ Subscription Components loaded');
