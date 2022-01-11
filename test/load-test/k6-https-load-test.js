import http from 'k6/http'
import { check } from 'k6'

// This uses k6 go lib to run concurrent requests against a cosmic web server.
// Run with: k6 run k6-http-load-test.js -s 30s:10

// Goals of the test:
// Use a testing tool that has reliable http request api and concurrency.
// Hit multiple endpoints in parallel to ensure server is using the correct handler logic per request. (go abstracts this but there should be some parallelism).
// Hit multiple resource types to simulate web app usage.
// TODO: Hit post endpoint to test sending data.
// Run with ramp up to see results of different loads.

export default function () {
    // Keep k6 urls for testing the config.
    // const responses = http.batch([
    //     ['GET', 'https://test.k6.io', null, { tags: { ctype: 'html' } }],
    //     ['GET', 'https://test.k6.io/style.css', null, { tags: { ctype: 'css' } }],
    //     ['GET', 'https://test.k6.io/images/logo.png', null, { tags: { ctype: 'images' } }],
    //     ['GET', 'https://test.k6.io/pi.php?decimals=3', null, { tags: { ctype: 'get' } }],
    // ])
    // check(responses[0], {
    //     'main page status was 200': (res) => res.status === 200,
    // })

    const responses = http.batch([
        ['GET', 'https://localhost:3000', null, { tags: { ctype: 'html' } }],
        ['GET', 'https://localhost:3000/style.css', null, { tags: { ctype: 'css' } }],
        // ['GET', 'https://localhost:3000/logo.png', null, { tags: { ctype: 'images' } }],
        ['GET', 'https://localhost:3000/foo', null, { tags: { ctype: 'get' } }],
        ['GET', 'https://localhost:3000/bar', null, { tags: { ctype: 'get' } }],
    ])
    check(responses[0], {
        'check / status': (res) => res.status === 200,
        'check / response': (res) => res.body === '<html><body></body></html>\n',
    })
    check(responses[1], {
        'check /style.css status': (res) => res.status === 200,
    })
    check(responses[2], {
        'check /foo response': (res) => res.body === 'foo from server',
    })
    check(responses[3], {
        'check /bar response': (res) => res.body === 'bar from server',
    })
}