// English legal policy texts — merged into translations via legal_policies.dart
const Map<String, String> legalPoliciesEn = {
  'legal_documents_title': 'Legal Documents',
  'terms_of_service_title': 'Terms of Service',
  'privacy_policy_title': 'Privacy Policy',
  'refund_policy_title': 'Refund Policy (Subscriptions)',
  'content_policy_title': 'Content Policy',
  'seller_rules_title': 'Seller Rules',
  'agree_terms_of_use':
      'I agree to the Terms of Service, Privacy Policy, Refund Policy, Content Policy, and Seller Rules',
  'must_agree_terms': 'You must agree to all legal policies to register',
  'terms_of_use_title': 'Legal Documents',
  'terms_of_use_link': 'Legal Policies',
  'terms_of_use_content':
      'By creating a STORAQ account you agree to all policies listed below. Tap any policy to read the full text.',
  'terms_of_service_content': '''STORAQ — Terms of Service
Last updated: June 2026

1. ACCEPTANCE
By accessing or using the STORAQ mobile application, web services, or admin tools ("Service"), you agree to these Terms of Service. If you do not agree, do not use the Service.

2. ABOUT STORAQ
STORAQ is a local marketplace and point-of-sale platform that connects store owners with customers. Store owners may list products online, manage inventory, process in-store orders, and use optional paid features. Customers may browse nearby stores, search products, chat with sellers, leave reviews, and report content.

3. ELIGIBILITY
- You must be at least 18 years old (or the age of majority in your jurisdiction) to create an account.
- You must provide accurate registration information and keep it up to date.
- One account per person. Fake, duplicate, or impersonation accounts may be terminated.
- Store owners must provide valid store details including a physical location.

4. ACCOUNT TYPES
- Customer: browse stores, place orders, chat, review, and report content.
- Store owner: operate a store, list products, manage workers, subscriptions, and analytics.
- Worker: invited staff with permissions set by the store owner (e.g., inventory access).
- Admin: platform operators with moderation and verification privileges.

5. YOUR RESPONSIBILITIES
- Keep your password confidential. You are responsible for activity under your account.
- Use the Service lawfully and in accordance with our Content Policy and Seller Rules.
- Do not attempt to bypass security, scrape data, or interfere with platform operations.
- Do not use automated tools to create accounts, upload content, or send messages.

6. MARKETPLACE ROLE
STORAQ is an intermediary platform. We do not manufacture, stock, ship, or guarantee products listed by store owners. Transactions between buyers and sellers are between those parties. STORAQ is not a party to sale contracts and is not responsible for product quality, safety, legality, delivery, or disputes arising from transactions.

7. SUBSCRIPTIONS & PAID FEATURES
- Every store receives 5 free online product slots.
- Paid subscription tiers (Starter, Business, Pro, Enterprise) unlock additional online slots and are billed monthly in 30-day periods.
- Payments may be made via authorized payment agents (cash) or, when available, card processors.
- Sponsored product placements are separate paid features subject to their own payment terms.
- Promo codes may grant discounts or temporary tier access per their stated conditions.

8. INTELLECTUAL PROPERTY
- STORAQ name, logo, and app design are our property. You may not copy or misuse them.
- You retain ownership of content you upload (product images, descriptions, store branding). By uploading, you grant STORAQ a non-exclusive license to display, store, and process that content to operate the Service (including image search features).

9. SUSPENSION & TERMINATION
We may suspend or terminate accounts that violate these Terms, our Content Policy, or Seller Rules. Grounds include prohibited products, fraud, bulk spam uploads, duplicate image abuse, high return rates, or abusive behavior. You may delete your account at any time in app settings.

10. DISCLAIMERS
THE SERVICE IS PROVIDED "AS IS" WITHOUT WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT. WE DO NOT GUARANTEE UNINTERRUPTED OR ERROR-FREE OPERATION.

11. LIMITATION OF LIABILITY
TO THE MAXIMUM EXTENT PERMITTED BY LAW, STORAQ AND ITS OPERATORS SHALL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS, DATA, OR GOODWILL ARISING FROM YOUR USE OF THE SERVICE.

12. CHANGES
We may update these Terms. Material changes will be reflected in the "Last updated" date. Continued use after changes constitutes acceptance.

13. CONTACT
For questions about these Terms, open a support ticket in the app or contact your regional STORAQ representative.''',
  'privacy_policy_content': '''STORAQ — Privacy Policy
Last updated: June 2026

1. INTRODUCTION
This Privacy Policy explains how STORAQ ("we", "us") collects, uses, stores, and shares information when you use our marketplace and POS application.

2. INFORMATION WE COLLECT

Account & identity:
- Full name, email address, phone number, and password (stored as a secure hash, never plain text)
- Account role (customer, store owner, worker, or admin)
- Preferred language
- Profile avatar (optional)
- Email verification status and one-time verification codes

Store owner data:
- Store name, city, country, village/area description, store phone number
- GPS coordinates (latitude/longitude) for location-based discovery
- Store logo/image, currency display settings, QR/deep-link identifiers
- Product listings: names, prices, quantities, descriptions, barcodes, categories, images
- Order and sales history, receipt numbers, payment methods, customer names/phones on receipts
- Expense records and customer credit ledgers (store-side bookkeeping)
- Worker invitations and staff permissions

Customer & usage data:
- Browsing activity: store visits, product views, search queries (linked to your account when logged in)
- Favorites (products and stores) — stored locally and synced when available
- Chat messages with stores
- Reviews (star rating and optional comment)
- Content reports (target type, reason, metadata)
- Support tickets and messages (text; images only when admin-approved)

Device & local storage:
- Viewer location (country, city, village, coordinates) cached on device for filters and currency display
- Offline SQLite cache: products, pending orders, stock changes for offline POS use
- App preferences (language, theme) in device storage

Technical & security data:
- Failed login attempts and OTP verification records
- Product image hashes and embeddings for duplicate detection and visual search
- Cloudflare Turnstile token during registration (anti-bot)

3. HOW WE USE YOUR INFORMATION
- Provide, operate, and improve the marketplace and POS features
- Display stores and products to nearby customers
- Verify identity via email codes and prevent abuse
- Process orders, receipts, subscriptions, and sponsored placements
- Provide analytics to store owners (revenue, visits, views, inventory alerts)
- Detect fraud, spam, and policy violations (automated flagging)
- Respond to support requests and content reports
- Comply with legal obligations

4. THIRD-PARTY SERVICES
- Cloudflare Turnstile: bot protection during registration (subject to Cloudflare's privacy policy)
- OpenStreetMap / geocoding services: map display and address lookup
- Email delivery: verification codes and notifications
We do not sell your personal information to third parties.

5. INFORMATION SHARING
- Public marketplace: store names, locations, product listings, and reviews are visible to other users.
- Order fulfillment: your name and phone may be visible to store staff you interact with.
- Workers: store owners may grant staff access to inventory and store data per permissions set.
- Legal: we may disclose information if required by law or to protect rights, safety, and platform integrity.
- We do NOT sell personal data to advertisers or data brokers.

6. DATA RETENTION
- Active account data is retained while your account exists.
- Deleted accounts: personal data is removed; order history may be retained in anonymized/denormalized form for bookkeeping.
- Support tickets, reports, and moderation records may be retained for compliance and dispute resolution.
- Analytics aggregates may be retained in de-identified form.

7. YOUR RIGHTS & CHOICES
- Access and update profile information in app settings.
- Change password (invalidates existing sessions).
- Delete your account in app settings (removes store, products, and uploads for store owners).
- Control location sharing via device permissions.
- Contact support for data inquiries.

8. SECURITY
We use industry-standard measures including password hashing, HTTPS, JWT session tokens, rate limiting, and access controls. No system is 100% secure; report suspected breaches via support.

9. CHILDREN
STORAQ is not directed at children under 13 (or 16 where applicable). We do not knowingly collect data from children. Contact us to request deletion if you believe a child provided data.

10. INTERNATIONAL USERS
Data may be processed on servers in regions where we or our providers operate. By using STORAQ you consent to such processing.

11. CHANGES
We may update this policy. The "Last updated" date reflects the current version. Continued use constitutes acceptance.

12. CONTACT
For privacy questions, open a support ticket in the app.''',
  'refund_policy_content': '''STORAQ — Refund Policy (Subscriptions)
Last updated: June 2026

This policy applies to paid store subscription plans. Sponsored product payments are non-refundable once a campaign is verified and activated (see Content Policy and Seller Rules).

1. SUBSCRIPTION PLANS
- Free: 5 online product slots at no cost.
- Paid tiers: Starter (\$4.99/mo), Business (\$14.99/mo), Pro (\$39.99/mo), Enterprise (\$99.99/mo) — prices in USD, subject to change with notice.
- Each paid period lasts 30 days from admin verification of payment.

2. PAYMENT METHODS
- Syria Agent (cash): pay an authorized agent with your reference code. Activation occurs after manual admin verification.
- Stripe (card): when available, processed through Stripe's payment infrastructure. Until fully launched, card payments may show as "coming soon."

3. GENERAL REFUND RULES
- Subscription fees are generally non-refundable once payment is verified and the 30-day period is activated.
- Unused days within an active period are not prorated or refunded.
- Downgrading or canceling does not entitle you to a refund for the current period; your plan simply expires at the end of the paid term and reverts to the Free tier (5 slots).

4. EXCEPTIONS — WE MAY ISSUE REFUNDS OR CREDITS WHEN:
- Duplicate payment for the same period (same reference code verified twice).
- Payment verified in error by admin (documented mistake).
- Technical failure preventing any subscription benefit for 72+ consecutive hours after activation.
- Fraudulent charge reported within 7 days with supporting evidence.

All exceptions are at STORAQ's sole discretion. Contact support with your payment reference code.

5. DISPUTE PROCESS
- Open a support ticket within 7 days of payment verification.
- Include: store name, reference code, payment date, amount paid, and reason for dispute.
- We will review and respond within 14 business days.
- Approved refunds for agent (cash) payments are returned via the same agent network or account credit, as applicable.

6. PROMO CODES
- Promo codes granting tier access or discounts are promotional offers with no cash value.
- Promo-granted tiers expire per code terms and are not refundable.

7. EXPIRATION & CANCELLATION
- Subscriptions expire automatically after 30 days unless renewed.
- No action is required to cancel; simply do not renew.
- Upon expiration, excess online products beyond the Free tier limit (5) are automatically taken offline.

8. CHARGEBACKS
Initiating a chargeback without first contacting support may result in account suspension pending investigation.

9. CHANGES
We may update this policy. Continued subscription purchases after changes constitute acceptance.

10. CONTACT
Open a support ticket in the app (category: Billing) for refund inquiries.''',
  'content_policy_content': '''STORAQ — Content Policy
Last updated: June 2026

This policy applies to all user-generated content on STORAQ including product listings, images, reviews, chat messages, and support communications.

1. PROHIBITED CONTENT
You may not post, list, or promote:
- Illegal goods or services under applicable law
- Counterfeit, replica, or stolen goods
- Weapons, explosives, or hazardous materials (where restricted)
- Controlled substances or unlicensed pharmaceuticals
- Content promoting violence, terrorism, or self-harm
- Hate speech, harassment, or discrimination targeting protected groups
- Sexually explicit content involving minors (zero tolerance — immediate ban and report to authorities)
- Malware, phishing, or fraudulent schemes
- Personal data of others without consent (doxxing)
- Spam, scams, or misleading/deceptive listings

2. PRODUCT LISTING STANDARDS
- Product names, descriptions, prices, and images must accurately represent the actual item.
- Do not use misleading photos (e.g., stock images for different products).
- Prices must be in a supported currency and reflect genuine intent to sell.
- Do not list the same product repeatedly to manipulate search results.

3. IMAGES & MEDIA
- Images must be your own or you must have rights to use them.
- No duplicate images across different accounts (detected automatically).
- No bulk automated uploads: creating 50+ products within one hour triggers review.
- Support ticket image attachments require admin approval before upload.

4. REVIEWS & CHAT
- Reviews must be honest and based on genuine experience.
- Store owners and their staff may not review their own store or products.
- Chat messages must not contain harassment, threats, or prohibited content.
- One active review per user per store/product (edits replace the previous review).

5. REPORTING
Users may report stores, products, or chat conversations with a reason (minimum 10 characters). Reports are reviewed by admins. False or abusive reporting may result in account action.

6. SPONSORED CONTENT
- Sponsored product badges must not be removed or misrepresented.
- Sponsored listings must still comply with all content rules.
- Geo-targeting scopes (radius, village, city, country, worldwide) must match the product's genuine availability.

7. ENFORCEMENT
Violations may result in:
- Content removal or rejection (first product approval required for new stores)
- Store deactivation (with documented reason)
- Manual approval mode (all new products require admin review)
- Account termination
- Referral to law enforcement for illegal content

Automated systems flag: bulk uploads, cross-account duplicate images, and high order return rates (>30% on 10+ orders).

8. APPEALS
If your store is deactivated or content removed, open a support ticket explaining why the action should be reversed. Decisions are final at STORAQ's discretion.

9. CHANGES
We may update this policy. Continued use constitutes acceptance.''',
  'seller_rules_content': '''STORAQ — Seller Rules
Last updated: June 2026

These rules apply to all store owners and authorized workers on STORAQ.

1. STORE SETUP
- Provide accurate store name, location (GPS), contact phone, and area description.
- Your first online product requires admin approval before appearing on the marketplace.
- Keep store information current. Misleading locations harm customer trust and may lead to deactivation.

2. PRODUCT MANAGEMENT
- Maximum 50 new products per store per day.
- Free tier: 5 products may be listed online simultaneously.
- Paid tiers: Starter (25), Business (100), Pro (500), Enterprise (2000) online slots.
- Products marked "offline" are stored in your catalog but hidden from the marketplace.
- Delete products you no longer sell. Do not leave ghost listings.

3. PRICING & INVENTORY
- Keep prices and stock quantities accurate.
- Supported currencies with automatic display conversion per store settings.
- Low-stock alerts help you manage inventory — set appropriate thresholds.
- Honor prices shown at time of customer inquiry or order.

4. IMAGES & DESCRIPTIONS
- Use clear, accurate photos of the actual product.
- Include relevant details: condition, size, brand, specifications.
- Barcodes are optional but recommended for POS scanning.
- Do not reuse identical images across multiple accounts.

5. POINT OF SALE (POS)
- Process orders honestly. Record payment method and optional customer details accurately.
- Offline mode caches data locally; sync when connected to avoid discrepancies.
- Customer credit ledgers are your responsibility — maintain accurate records.
- Expense tracking is for your bookkeeping; STORAQ does not provide tax advice.

6. WORKERS & STAFF
- Invite workers via email. They must accept the invitation.
- Grant inventory access only to trusted staff.
- You are responsible for all actions taken by your workers on your store.

7. SUBSCRIPTIONS
- Pay subscription fees before expecting tier benefits.
- Use the reference code provided when paying via authorized agents.
- Subscriptions last 30 days from verification. Plan renewals accordingly.
- When a subscription expires, products beyond the Free limit are taken offline automatically.

8. SPONSORED PRODUCTS
- Request sponsorship for specific products with chosen geo-scope and duration.
- Pay the quoted amount via authorized agents. Campaigns activate after admin verification.
- Sponsored placements are non-refundable once active.
- Do not manipulate sponsored badges or targeting.

9. REVIEWS & REPUTATION
- Do not solicit fake reviews or offer incentives for positive reviews.
- To request review removal, open a support ticket (category: review_removal) — admins decide.
- High return rates (>30% on 10+ orders) trigger automated review and possible deactivation.

10. CUSTOMER COMMUNICATION
- Respond to chat messages professionally.
- Do not share customer personal data outside the transaction context.
- Report abusive customers via the report feature.

11. PROHIBITED SELLER CONDUCT
- Selling counterfeit, illegal, or prohibited items
- Price gouging or bait-and-switch tactics
- Bulk spam uploads or catalog flooding
- Circumventing subscription slot limits
- Creating multiple accounts to evade restrictions
- Manipulating analytics or view counts

12. ENFORCEMENT & APPEALS
- Admins may deactivate your store with a required reason.
- Flagged stores may be placed in manual approval mode.
- You may appeal via support tickets. Reinstatement is not guaranteed.
- Repeated violations result in permanent ban.

13. TAXES & COMPLIANCE
You are solely responsible for taxes, licenses, and legal compliance in your jurisdiction. STORAQ does not collect or remit sales tax on your behalf.

14. CONTACT
For seller support, use in-app support tickets or chat with platform administrators.''',
};
