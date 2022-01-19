// Run with: deno run --unstable --allow-read --allow-net test/load-test/deno-server.js

const listener = Deno.listenTls({
    port: 3000,
    certFile: 'deps/https/localhost.crt',
    keyFile: 'deps/https/localhost.key',
    alpnProtocols: ["h2", "http/1.1"],
});
while (true) {
    handleNewConnection(await listener.accept());
}

async function handleNewConnection(conn) {
    const httpConn = Deno.serveHttp(conn);
    while (true) {
        try {
            const e = await httpConn.nextRequest();
            const {request:req, respondWith:res}=e;
            // await new Promise(r => setTimeout(r, 60000));
            const url = new URL(req.url);
            if (url.pathname == '/foo') {
                await res(new Response('foo from server'));
            } else if (url.pathname == '/bar') {
                await res(new Response('bar from server'));
            }
        } catch {
            break;
        }
    }
}