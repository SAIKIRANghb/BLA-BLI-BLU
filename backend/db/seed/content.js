/**
 * Seed content - faithful recreation of the blabliblulife.com storefront
 * chrome: navigation, home page composition, FAQs, policy pages and coupons.
 * Prices/strings match the live site (Sep 2026).
 */

const CDN = 'https://blabliblulife.com/cdn/shop/files';

/** Ordered navigation / merchandising collections. */
export const COLLECTIONS = [
  { handle: 'new-arrivals', title: 'New Arrivals', description: 'Fresh drops, just landed.', imageUrl: `${CDN}/841x1161_cace3041-1d18-4407-b683-19d07a3b0162.jpg?v=1787660013&width=800`, position: 1 },
  { handle: 'perfume', title: 'Parfum - 100ml', description: '25% oil concentration parfums that last 12+ hours.', imageUrl: `${CDN}/5_8d236b2f-fca3-4d7a-98b0-7099fb011f77.jpg?v=1758028036&width=600`, position: 2 },
  { handle: 'best-perfumes-for-men', title: 'Best Perfumes For Men', description: 'Long lasting fragrances built for him.', imageUrl: `${CDN}/by_the_beach_1f2c7a8c-21dd-4003-ac1d-b41838dcd907.jpg?v=1761643319&width=600`, position: 3 },
  { handle: 'perfumes-for-women', title: 'Perfumes For Women', description: 'Sweet, bold and unapologetic.', imageUrl: `${CDN}/Red_BLA_BLU_perfume_gift_set.jpg?v=1779453383&width=600`, position: 4 },
  { handle: 'unisex-perfume', title: 'Unisex Perfume', description: 'Scents that do not ask permission.', imageUrl: `${CDN}/10_205782e9-1600-4759-931f-8580989eaa23.jpg?v=1761642574&width=600`, position: 5 },
  { handle: 'oud-perfumes', title: 'Oud Perfumes', description: 'Rich, resinous and unforgettable.', imageUrl: `${CDN}/8_3fb29c77-cfd2-4494-b7ec-d9ba261dd4ad.jpg?v=1761642180&width=600`, position: 6 },
  { handle: 'perfume-gift-sets', title: 'Perfume Gift Set', description: 'Three scents, one perfect gift.', imageUrl: `${CDN}/gift-set-update.jpg?v=1761812257&width=600`, position: 7 },
  { handle: 'gourmand-perfume', title: 'Gourmand', description: 'Dessert-worthy scents you can eat (please do not).', imageUrl: `${CDN}/Bla_Bli_Blu_Berry_Baddie_perfume.jpg?v=1790156969&width=600`, position: 8 },
  { handle: 'perfume-trial-pack', title: 'Perfume Trial Pack', description: 'Try before you buy. 100% redeemable.', imageUrl: `${CDN}/7_f9cd7a88-4386-4295-82a3-057853b4d54c.jpg?v=1758028036&width=600`, position: 9 },
  { handle: 'body-wash', title: 'Body Wash', description: 'Perfumed body washes from ₹249.', imageUrl: `${CDN}/Body-Wash_jpg.jpg?v=1773388357&width=600`, position: 10 },
  { handle: 'car-perfume', title: 'Car Perfume', description: '40ml fragrances for your daily drive.', imageUrl: `${CDN}/1_cca05875-d98f-46f3-a443-363b97681ab1.jpg?v=1783009497&width=600`, position: 11 },
  { handle: 'build-your-own-box', title: 'Build Your Own Box', description: 'Pick your scents, we box them up.', imageUrl: `${CDN}/byob-combined.jpg?v=1763041428&width=600`, position: 12 },
  { handle: 'two-scents', title: 'Two Scents', description: '75ml parfum + 8ml pure oil, one feeling.', imageUrl: `${CDN}/1._primary_image_grey_bg_68cc7c5e-276d-4698-b743-e06c4848e212.jpg?v=1776323875&width=600`, position: 13 },
];

/** Handle rules: tag/attribute based membership for every collection. */
export const COLLECTION_RULES = [
  { handle: 'new-arrivals', tags: ['New Arrivals'] },
  { handle: 'perfume', tags: ['parfum', 'perfume'] },
  { handle: 'best-perfumes-for-men', tags: ['men', 'for men'] },
  { handle: 'perfumes-for-women', tags: ['women', 'for women'] },
  { handle: 'unisex-perfume', tags: ['unisex'] },
  { handle: 'oud-perfumes', tags: ['oud', 'Oud Unisex'] },
  { handle: 'perfume-gift-sets', tags: ['gift-box', 'gift set men', 'gift set women', 'gift set oud'] },
  { handle: 'perfume-trial-pack', tags: ['reedeemable', 'reedeemable449', 'kit', 'ultimate set'] },
  { handle: 'body-wash', tags: ['body-wash'] },
  { handle: 'car-perfume', tags: ['Car-fragrance'] },
  { handle: 'build-your-own-box', tags: ['Own Box', 'customize'] },
  { handle: 'two-scents', tags: ['two-scents'] },
  { handle: 'gourmand-perfume', handles: ['happy-bananana', 'berry-baddie', 'watermelon-buddy', 'mango-so-goated'] },
];

/** Merchandising order for the home page "Bestseller | New Arrivals" carousel. */
export const FEATURED_HANDLES = [
  'love-drunk-best-unisex-perfume',
  'watermelon-buddy',
  'old-money-long-lasting-perfume-for-men',
  'perfume-gift-set-for-men',
  'perfume-gift-set-for-women',
  'mango-so-goated',
  'berry-baddie',
  'happy-bananana',
  'billionaire-vibes-men-perfume',
  'lil-black-dress-perfume-for-women',
  'habibi-unisex-perfume',
  'love-drunk-body-wash',
  'bla-bli-blu-ultimate-experience-set',
  'self-made-perfume-body-wash-for-men',
  'old-money-body-wash',
  'by-the-beach',
  'vetiver-oud',
  'hot-af-women-perfume',
];

/** Home page composition, mirrored from the live storefront. */
export const HOME = {
  announcement: 'Fragrance Brand of The Year | Free Shipping | COD Available |',
  announcementLink: '/collections/all',
  heroSlides: [
    {
      desktopUrl: `${CDN}/Home_desk_b65fe8ac-282d-4d94-8bfc-4dfa148e11c4.jpg?v=1790155436&width=1920`,
      mobileUrl: `${CDN}/Home_mob_08176a08-f05f-4e0c-9056-de921f7c7b35.jpg?v=1790155465&width=800`,
      link: '/collections/gourmand-perfume',
      alt: 'Gourmand collection',
    },
    {
      desktopUrl: `${CDN}/2400x1020_hero_banner_937f8871-1cca-451a-b641-d99dcedf7edc.jpg?v=1787659909&width=1920`,
      mobileUrl: `${CDN}/841x1161_cace3041-1d18-4407-b683-19d07a3b0162.jpg?v=1787660013&width=800`,
      link: '/collections/all',
      alt: 'Shop all',
    },
    {
      desktopUrl: `${CDN}/2400x1020_hero_banner_0ff8f839-d9ee-4d01-b58a-686a02c47d2e.jpg?v=1784270750&width=1920`,
      mobileUrl: `${CDN}/841x1161_819faf91-c6c1-490b-990a-f51388e634b3.jpg?v=1784270749&width=800`,
      link: '/collections/car-perfume',
      alt: 'Car perfume',
    },
    {
      desktopUrl: `${CDN}/2400x1020_hero_banner_bodywash_loofah_pouch.jpg?v=1774866805&width=1920`,
      mobileUrl: `${CDN}/841x1161_hero_banner_bodywash_loofah_pouch.jpg?v=1774866805&width=800`,
      link: '/products/build-your-own-body-wash',
      alt: 'Build your own body wash',
    },
    {
      desktopUrl: `${CDN}/byob_2400x1020_hero_banner__1.jpg?v=1763040838&width=1920`,
      mobileUrl: `${CDN}/byob_841x1161_hero_banner_1.jpg?v=1763040843&width=800`,
      link: '/collections/build-your-own-box',
      alt: 'Build your own box',
    },
  ],
  collectionSection: {
    title: 'Our Collection',
    tiles: [
      { title: 'Build your own box', imageUrl: `${CDN}/byob-combined.jpg?v=1763041428&width=600`, startingPricePaise: 75000, link: '/collections/build-your-own-box' },
      { title: 'Parfum - 100 ml', imageUrl: `${CDN}/5_8d236b2f-fca3-4d7a-98b0-7099fb011f77.jpg?v=1758028036&width=600`, startingPricePaise: 57500, link: '/collections/perfume' },
      { title: 'Perfume Gift Set', imageUrl: `${CDN}/gift-set-update.jpg?v=1761812257&width=600`, startingPricePaise: 80000, link: '/collections/perfume-gift-sets' },
      { title: 'Gourmand-75Ml', imageUrl: `${CDN}/Bla_Bli_Blu_Berry_Baddie_perfume.jpg?v=1790156969&width=600`, startingPricePaise: 80000, link: '/collections/gourmand-perfume' },
      { title: 'Body Wash', imageUrl: `${CDN}/Body-Wash_jpg.jpg?v=1773388357&width=600`, startingPricePaise: 24900, link: '/collections/body-wash' },
      { title: 'Perfume Trial Pack', imageUrl: `${CDN}/7_f9cd7a88-4386-4295-82a3-057853b4d54c.jpg?v=1758028036&width=600`, startingPricePaise: 39900, link: '/collections/perfume-trial-pack', caption: '100% Redeemable' },
    ],
  },
  trialSection: {
    title: 'Game Changer Trial Set',
    tagline: '❤️ smell it, love it — or get 100% money back. Redeem your discovery set cost on any full-size bottle.',
    tiles: [
      { title: 'For Him', badge: '100% Redeemable', imageUrl: `${CDN}/10_b04b6695-e734-4d07-b30e-0672006dba47.jpg?v=1758028036&width=3000`, link: '/products/best-perfume-trial-pack-for-men' },
      { title: 'Oud Unisex', badge: '100% Redeemable', imageUrl: `${CDN}/4_1a31f6a9-7a71-40d0-851d-b438cb3adc9f.jpg?v=1758028036&width=3000`, link: '/products/habibi' },
      { title: 'For Her', badge: '100% Redeemable', imageUrl: `${CDN}/9_a54e26da-9869-4ca8-bebd-9777e3296bb0.jpg?v=1758028037&width=3000`, link: '/products/buy-perfume-trial-pack-for-women' },
      { title: '14 Unique Perfumes Travel Set', badge: '', imageUrl: `${CDN}/450-450-01.jpg?v=1769062458&width=3000`, link: '/products/bla-bli-blu-ultimate-experience-set' },
    ],
  },
  featuredTitle: 'Bestseller | New Arrivals',
  featuredHandles: FEATURED_HANDLES,
  banners: [
    { imageUrl: `${CDN}/new-banner_-aug23.webp?v=1758432602&width=2000`, mobileUrl: `${CDN}/new-banner_-aug23.webp?v=1758432602&width=1000`, link: '/collections/perfume-trial-pack', alt: 'Try before you buy' },
    { imageUrl: `${CDN}/home_page_comms_banner_web.png?v=1753262279&width=2000`, mobileUrl: `${CDN}/home_page_comms_banner_mb.png?v=1753262279&width=1000`, link: '/collections/all', alt: 'Free shipping on orders above ₹399' },
  ],
  claims: {
    imageUrl: `${CDN}/claims_webp_be45e9be-bb66-4fbf-b128-1315394ae84e.webp?v=1758432601&width=1000`,
    points: [
      '12+ hours of long lasting fragrance',
      '25% perfume oil concentration',
      'Free shipping above ₹399',
      '100% cash on delivery available',
      '100% redeemable trial packs',
      'Cruelty free & made in India',
    ],
  },
  faqTitle: 'Faqs',
  faqIntro: 'Curiosity didn’t kill the cat - it just brought you here!\nYou got questions. We\'ve got answers. If anything else pops up, WhatsApp us anytime.',
  newsletter: { title: 'Logged in yet?', subtitle: 'Wild deals are waiting. make sure not to miss out!', cta: 'Get in. Now.', link: '/account' },
  brandTagline: 'Against the Ordinary!',
  social: [
    { platform: 'Instagram', url: 'https://www.instagram.com/blabliblu.official/' },
    { platform: 'YouTube', url: 'https://www.youtube.com/@BLABLIBLU.OFFICIAL/' },
    { platform: 'LinkedIn', url: 'https://www.linkedin.com/company/blablibluofficial/' },
    { platform: 'X', url: 'https://x.com/blablibluHQ' },
    { platform: 'Facebook', url: 'https://www.facebook.com/blabliblu.official' },
  ],
  footer: {
    shop: [
      { title: 'Perfume Trial Pack', link: '/collections/perfume-trial-pack' },
      { title: 'Parfum - 100ml', link: '/collections/perfume' },
      { title: 'Shop All', link: '/collections/all' },
      { title: 'Perfume gift set', link: '/collections/perfume-gift-sets' },
      { title: 'Unisex Perfume', link: '/collections/unisex-perfume' },
    ],
    information: [
      { title: 'About Us', link: '/pages/about-us' },
      { title: 'Terms of Service', link: '/pages/terms-of-service' },
      { title: 'Privacy Policy', link: '/pages/privacy-policy' },
      { title: 'Shipping Policy', link: '/pages/shipping-policy' },
      { title: 'Refund Policy', link: '/pages/refund-policy' },
      { title: 'Exchange Policy', link: '/pages/exchange-policy' },
      { title: 'Cashback Terms', link: '/pages/cashback-terms-conditions' },
    ],
    contact: [
      { title: 'Contact', link: '/pages/contact' },
      { title: 'Track Order', link: '/track' },
      { title: 'Bulk Orders - Query Form', link: '/pages/wholesale-contact-form' },
    ],
  },
  support: {
    email: 'support@blabliblulife.com',
    phone: '+91 9220508119',
    whatsapp: 'https://wa.me/919220508119',
    hours: 'Monday–Saturday, 10 AM to 7 PM',
    address: '3rd Floor, Suncity Success Tower, Golf Course Extension Road, Sector 65, Gurgaon, Haryana – 122002',
  },
  scamAlert: {
    title: 'Scam Alert',
    body: 'We have noticed a rise in fraudulent activities through calls, SMS, WhatsApp messages, emails, and other mediums.',
    points: [
      'Bla Bli Blu will never ask for OTPs, passwords, bank details, or payments via calls, SMS, WhatsApp, or email.',
      'We never request payments for any promotional activities through unauthorised channels.',
      'If you receive any such communication, reach out to us at +91 9220508119 or support@blabliblulife.com.',
    ],
    closing: 'Stay safe!',
  },
  copyright: '© 2026, Bla Bli Blu - Powered by Raritiq Designs Pvt. Ltd.',
};

/** Store FAQ list (verbatim from the site). */
export const FAQS = [
  { category: 'Orders', question: 'What do you offer?', answer: 'We offer perfumes and gift sets in men, women, and unisex variants which includes Perfume trial pack, full-size, and pocket perfume bottles. You can also build your own customized box of favorite fragrances.' },
  { category: 'Orders', question: 'What if I enter the wrong address?', answer: 'Contact our support team immediately to fix it before shipping.' },
  { category: 'Orders', question: 'How long does delivery take?', answer: 'Our orders usually take 3-7 business days to deliver the order at your doorstep.' },
  { category: 'Orders', question: 'How can I track my order?', answer: 'After placing an order, you’ll receive a tracking link by SMS/email. You can also use the “Track Order” option in the app to know the details of your order.' },
  { category: 'Products', question: 'Are your perfumes long-lasting?', answer: 'Our perfumes are designed to last for about 10-12 hours, depending on your skin type, weather, and how you apply them.' },
  { category: 'Shipping', question: 'Do you offer free shipping?', answer: 'Yes, we provide free shipping on all orders above ₹399.' },
  { category: 'Shipping', question: 'Do you have bulk purchase offers?', answer: 'Yes, we offer special pricing for bulk purchase and corporate orders. Please contact our support team for more details.' },
  { category: 'Support', question: 'How do I contact customer support?', answer: 'You can email us at support@blabliblulife.com or call/WhatsApp us at +91 9220508119 (Monday–Saturday, 10 AM to 7 PM).' },
  { category: 'Support', question: 'What is your refund policy?', answer: 'We offer refunds for damaged or incorrect orders. Reach out within 7 days of delivery with your order number and our team will sort it out.' },
];

/** Static pages (legal / about). */
export const PAGES = [
  {
    handle: 'about-us',
    title: 'About Us',
    body: 'Bla Bli Blu is an Indian fragrance house built on one stubborn idea: luxury smelling perfume should not cost a luxury. We blend in small batches, keep the perfume oil concentration at 25%, and build every scent from real customer feedback instead of boardroom guesses.\n\nFrom our 100% redeemable trial packs to the build-your-own box, everything we make is designed so you can find your signature scent without gambling your money.\n\nAgainst the Ordinary!',
  },
  {
    handle: 'terms-of-service',
    title: 'Terms of Service',
    body: 'By accessing or purchasing from Bla Bli Blu you agree to our terms of service. Products are for personal use; resale without written consent is not permitted. We reserve the right to cancel orders that appear fraudulent or to update pricing and availability at any time.',
  },
  {
    handle: 'privacy-policy',
    title: 'Privacy Policy',
    body: 'We collect only the data needed to fulfil your order: name, contact details, shipping address and order history. We never sell your data. Payment information is handled by our payment partners and is never stored on our servers.',
  },
  {
    handle: 'shipping-policy',
    title: 'Shipping Policy',
    body: 'Free shipping on all orders above ₹399. Orders are dispatched within 24-48 hours and delivered in 3-7 business days across India. Cash on delivery is available on all pincodes we serve.',
  },
  {
    handle: 'refund-policy',
    title: 'Refund Policy',
    body: 'Damaged, defective or incorrectly shipped products are eligible for a refund or replacement when reported within 7 days of delivery with order number and unboxing proof. Refunds are processed to the original payment method within 5-7 business days.',
  },
  {
    handle: 'exchange-policy',
    title: 'Exchange Policy',
    body: 'Sealed, unopened products can be exchanged within 7 days of delivery. Trial packs and opened bottles cannot be exchanged for hygiene reasons.',
  },
  {
    handle: 'cashback-terms-conditions',
    title: 'Cashback Terms & Conditions',
    body: 'Cashback is credited as store credit and auto-applied at checkout. Trial pack value is 100% redeemable against any full-size bottle. Cashback cannot be clubbed with other coupons and expires 30 days after issue.',
  },
  {
    handle: 'contact',
    title: 'Contact',
    body: 'Email: support@blabliblulife.com\nCall / WhatsApp: +91 9220508119\nHours: Monday–Saturday, 10 AM to 7 PM\n\nRaritiq Designs Pvt Ltd, 3rd Floor, Suncity Success Tower, Golf Course Extension Road, Sector 65, Gurgaon, Haryana – 122002.',
  },
  {
    handle: 'wholesale-contact-form',
    title: 'Bulk Orders - Query Form',
    body: 'Planning gifting for your team, college fest or wedding? Write to support@blabliblulife.com with quantity, timeline and pincode and our bulk orders team will share custom pricing within one business day.',
  },
];

/** Promotion codes available at checkout. */
export const COUPONS = [
  { code: 'WELCOME10', coupon_type: 'percent', value: 10, min_order_paise: 49900, max_discount_paise: 20000, active: true, description: '10% off your first order above ₹499' },
  { code: 'FLAT100', coupon_type: 'flat', value: 10000, min_order_paise: 99900, max_discount_paise: null, active: true, description: '₹100 off on orders above ₹999' },
  { code: 'FREESHIP', coupon_type: 'free_shipping', value: 0, min_order_paise: 0, max_discount_paise: null, active: true, description: 'Free shipping, no minimum' },
];
