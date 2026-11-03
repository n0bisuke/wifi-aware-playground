#!/usr/bin/env node
// Relays 127.0.0.1:27015 to macOS's usbmuxd socket so the container's xtool can
// reach iPhones connected to the Mac. Run this on the Mac, not in the container.
// The listener is fixed to the loopback address so it is never exposed to the LAN.
import net from "node:net";

const HOST = "127.0.0.1";
const PORT = Number(process.env.USBMUXD_RELAY_PORT ?? 27015);
const SOCKET_PATH = process.env.USBMUXD_RELAY_SOCKET ?? "/var/run/usbmuxd";

const server = net.createServer((client) => {
  const upstream = net.connect(SOCKET_PATH);

  const onError = (side) => (error) => {
    console.error(`${side}: ${error.message}`);
    client.destroy();
    upstream.destroy();
  };
  client.on("error", onError("client"));
  upstream.on("error", onError("usbmuxd"));

  client.pipe(upstream);
  upstream.pipe(client);
});

server.on("error", (error) => {
  console.error(`relay: ${error.message}`);
  process.exit(1);
});

server.listen(PORT, HOST, () => {
  console.log(`Relaying ${HOST}:${PORT} -> ${SOCKET_PATH} (Ctrl+C to stop)`);
});
