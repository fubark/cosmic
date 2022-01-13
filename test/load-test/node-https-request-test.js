const https = require('https');

// Run with: node test/load-test/node-https-request-test.js

process.env["NODE_TLS_REJECT_UNAUTHORIZED"] = 0;

(async () => {
    const start = process.hrtime()
    const tasks = [];
    for (let i = 0; i < 1000; i++) {
        tasks.push(get('https://localhost:3000/foo').then(text => {
            // assertEquals(text, 'foo from server')
        }))
        tasks.push(get('https://localhost:3000/bar').then(text => {
            // assertEquals(text, 'bar from server')
        }))
    }
    await Promise.all(tasks)
    const now = process.hrtime()
    console.log((now[0]*1000 + now[1]/1000000 - start[0]*1000 + start[1]/1000000) + 'ms');
})()

async function get(url) {
    return new Promise((resolve) => {
        https.get(url, res => {
            let data = ''
            res.on('data', chunk => { data += chunk }) 
            res.on('end', () => {
               resolve(data)
            })
        }) 
    })
}