/**
 * smoke.js - end-to-end check of the public API surface against a running
 * server (`npm start` in another terminal), then `npm run smoke`.
 *
 * Exercises: catalogue, content, auth, cart, coupons, checkout, tracking,
 * addresses, admin fulfilment.
 */
const BASE = process.env.API_BASE ?? 'http://localhost:4000/api';
const results = [];
let failures = 0;

async function call(name, fn, expect = []) {
  try {
    const { status, body } = await fn();
    const ok = (status >= 200 && status < 300) || expect.includes(status);
    if (!ok) failures += 1;
    const line = `${ok ? 'PASS' : 'FAIL'} ${String(status)} ${name} :: ${JSON.stringify(body).slice(0, 220)}`;
    results.push(line);
    console.log(line);
    return body;
  } catch (err) {
    failures += 1;
    const line = `FAIL ERR ${name} :: ${err.message}`;
    results.push(line);
    console.log(line);
    return null;
  }
}

const get = async (path, opts = {}) => {
  const res = await fetch(`${BASE}${path}`, opts);
  let body;
  try {
    body = await res.json();
  } catch {
    body = await res.text();
  }
  return { status: res.status, body };
};
const post = (path, body, opts = {}) =>
  get(path, { method: 'POST', headers: { 'content-type': 'application/json', ...(opts.headers ?? {}) }, body: JSON.stringify(body) });
const patch = (path, body, opts = {}) =>
  get(path, { method: 'PATCH', headers: { 'content-type': 'application/json', ...(opts.headers ?? {}) }, body: JSON.stringify(body) });
const del = (path, opts = {}) => get(path, { method: 'DELETE', ...(opts.headers ? { headers: opts.headers } : {}) });

async function main() {
  const health = await call('health', () => get('/health'));
  if (!health?.success) {
    console.log('Server is not running. Start it with `npm start` first.');
    process.exit(1);
  }

  const home = await call('home', () => get('/home'));
  await call('collections', () => get('/collections'));
  await call('products list', () => get('/products?limit=3&sort=price_asc'));
  await call('collection filter', () => get('/products?collection=body-wash&limit=2'));
  await call('product detail', () => get('/products/love-drunk-best-unisex-perfume'));
  await call('reviews', () => get('/products/love-drunk-best-unisex-perfume/reviews?limit=3'));
  await call('search', () => get('/products/search?q=oud'));
  await call('faqs', () => get('/faqs'));
  await call('page', () => get('/pages/about-us'));
  await call('invalid sort rejected', () => get('/products?sort=hack; DROP TABLE products'), [422]);

  // ---- identity -------------------------------------------------------
  const email = `smoke${Date.now()}@example.com`;
  const registered = await call('register', () => post('/auth/register', { name: 'Smoke Tester', email, password: 'password123' }));
  const token = registered?.data?.accessToken;
  const auth = { authorization: `Bearer ${token}` };
  await call('login', () => post('/auth/login', { email, password: 'password123' }));
  await call('login with wrong password', () => post('/auth/login', { email, password: 'wrong-password' }), [401]);
  await call('me', () => get('/auth/me', { headers: auth }));
  await call('me without token', () => get('/auth/me'), [401]);

  await call('save address', () =>
    post('/addresses', { label: 'Home', line1: '221B Baker Street', city: 'Gurugram', state: 'Haryana', pincode: '122002', phone: '9876543210' }, { headers: auth }),
  );
  await call('list addresses', () => get('/addresses', { headers: auth }));

  // ---- cart -----------------------------------------------------------
  const created = await call('create cart', () => post('/carts', {}));
  const cartId = created?.data?.id;
  const productId = home?.data?.featured?.[0]?.id;
  await call('add to cart', () => post(`/carts/${cartId}/items`, { productId, qty: 2 }));
  await call('get cart', () => get(`/carts/${cartId}`));
  const cart = await get(`/carts/${cartId}`);
  const lineId = cart.body?.data?.items?.[0]?.id;
  await call('update quantity', () => patch(`/carts/${cartId}/items/${lineId}`, { qty: 3 }));
  await call('apply coupon WELCOME10', () => post(`/carts/${cartId}/coupon`, { code: 'WELCOME10' }));
  await call('reject unknown coupon', () => post(`/carts/${cartId}/coupon`, { code: 'NOPE' }), [422]);
  await call('quote totals', () => post('/carts/quote', { subtotalPaise: 49900, code: 'WELCOME10' }));
  await call('quantity cap enforced', () => patch(`/carts/${cartId}/items/${lineId}`, { qty: 99 }), [422]);

  // ---- checkout -------------------------------------------------------
  const order = await call('place order', () =>
    post('/orders', {
      cartId,
      paymentMethod: 'cod',
      email,
      address: { name: 'Smoke Tester', phone: '9876543210', line1: '221B Baker Street', city: 'Gurugram', state: 'Haryana', pincode: '122002' },
    }),
  );
  const orderId = order?.data?.id;
  const orderNumber = order?.data?.orderNumber;
  await call('cart cleared after order', () => get(`/carts/${cartId}`));
  await call('order history', () => get('/orders', { headers: auth }));
  await call('order detail', () => get(`/orders/${orderId}`, { headers: auth }));
  await call('track by order number', () => get(`/orders/track?orderNumber=${orderNumber}&email=${encodeURIComponent(email)}`));
  await call('track with wrong email', () => get(`/orders/track?orderNumber=${orderNumber}&email=other@example.com`), [403]);
  await call('admin advance status', () => patch(`/admin/orders/${orderId}/status`, { status: 'confirmed' }, { headers: { 'x-api-key': 'blabliblu-admin' } }));
  await call('admin without key rejected', () => patch(`/admin/orders/${orderId}/status`, { status: 'shipped' }), [403]);

  // ---- cart merge ------------------------------------------------------
  const guestCart = await call('guest cart', () => post('/carts', {}));
  await post(`/carts/${guestCart?.data?.id}/items`, { productId, qty: 1 });
  await call('merge guest cart into account', () => post('/carts/merge', { cartId: guestCart?.data?.id }, { headers: auth }));

  // ---- qty 0 = remove line (PATCH contract) ----------------------------
  await del(`/carts/${cartId}`);
  await post(`/carts/${cartId}/items`, { productId, qty: 1 });
  const stocked = await get(`/carts/${cartId}`);
  const zeroLineId = stocked.body?.data?.items?.[0]?.id;
  await call('qty 0 accepted by PATCH', () => patch(`/carts/${cartId}/items/${zeroLineId}`, { qty: 0 }));
  const emptied = await get(`/carts/${cartId}`);
  const leftBehind = emptied.body?.data?.items?.length ?? -1;
  const removedByZero = leftBehind === 0;
  if (!removedByZero) failures += 1;
  results.push(`${removedByZero ? 'PASS' : 'FAIL'} 200 line removed by qty 0 :: ${leftBehind} line(s) left`);
  console.log(results[results.length - 1]);

  // ---- 404s ------------------------------------------------------------
  await call('unknown product 404', () => get('/products/does-not-exist'), [404]);
  await call('unknown route 404', () => get('/nope'), [404]);

  console.log(`\n${results.length - failures}/${results.length} checks passed`);
  process.exit(failures ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
