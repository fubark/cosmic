import { assertEquals } from "https://deno.land/std/testing/asserts.ts";

// Run with: DENO_TLS_CA_STORE=system deno test test/load-test/deno-https-request-test.js --allow-net

Deno.test('Concurrent fetch requests', async () => {
    const tasks = [];
    for (let i = 0; i < 1000; i++) {
        tasks.push(fetch('https://localhost:3000/foo').then(resp => resp.text()).then(text => {
            assertEquals(text, 'foo from server')
        }))
        tasks.push(fetch('https://localhost:3000/bar').then(resp => resp.text()).then(text => {
            assertEquals(text, 'bar from server')
        }))
    }
    await Promise.all(tasks)
})