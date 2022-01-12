// Test multiple async cs.http requests against: cs-server.js
// Run with: cosmic test cs-https-request-test.js

// Goals of the test:
// This is a load test on the client side cs.http requests.
// Make sure an async request doesn't affect a sync request.
// Hit different endpoints and ensure that each response returns to the original request task. 

const eq = cs.asserts.eq;

cs.test('Concurrent cs.http requests', async () => {
    const tasks = [];
    // TODO: Implement getAsync with libuv and increase the number of async requests.
    for (let i = 0; i < 10; i++) {
        tasks.push(cs.http.getAsync('https://localhost:3000/foo').then(text => {
            cs.asserts.eq(text, 'foo from server')
        }))
        tasks.push(cs.http.getAsync('https://localhost:3000/bar').then(text => {
            cs.asserts.eq(text, 'bar from server')
        }))
    }
    // Test sync request right after spawning async requests.
    eq(cs.http.get('https://localhost:3000/foo'), 'foo from server')
    await Promise.all(tasks)
})