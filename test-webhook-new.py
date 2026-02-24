#!/usr/bin/env python3
"""Webhook Test Script for Nextcloud Talk Channel.

This script tests the webhook endpoint with a test message.
Requires: python3, openssl
"""

import asyncio
import hashlib
import hmac
import json
import os
import subprocess
from pathlib import Path

try:
    import httpx
except ImportError:
    print("Error: httpx not installed")
    print("Install with: pip install httpx")
    exit(1)

try:
    from aiohttp import web
except ImportError:
    print("Error: aiohttp not installed")
    print("Install with: pip install aiohttp")
    exit(1)


async def test_webhook(port: int = 18790) -> None:
    """Run a webhook test."""
    print(f"🧪 Starting Webhook Test Script")
    print(f"📡 Gateway Port: {port}")

    # Print test config
    print("\n📋 Test Details:")
    print(f"   BASE_URL: https://cloud.example.com")
    print(f"   BOT_SECRET: your-shared-secret-min-40-chars")
    print(f"   WEBHOOK_PATH: /webhook/nextcloud_talk")
    print(f"   ROOM_TOKEN: testtoken123")

    # Create test payload
    test_payload = {
        "type": "Create",
        "actor": {"type": "users", "id": "testuser1", "displayName": "Test User 1"},
        "object": {
            "type": "comment",
            "id": "1",
            "name": "Test User 1",
            "content": "Hello Bot! What can you do?",
            "mediaType": "text/markdown",
        },
        "target": {"type": "room", "id": "testtoken123", "name": "Test Room"},
    }

    print("\n📤 Test Payload:")
    print(json.dumps(test_payload, indent=2))

    # Calculate signature
    print("\n🔐 HMAC Signature Calculation:")

    # IMPORTANT: bot_secret must come from config.json
    print("   Note: Test uses placeholder bot secret.")
    print("   Make sure to use your actual bot_secret from config.json")

    # Read bot_secret from config.json (if available)
    config_path = Path.home() / ".nanobot" / "config.json"
    if config_path.exists():
        import json

        config_data = json.loads(config_path.read_text())
        bot_secret = (
            config_data.get("channels", {})
            .get("nextcloud_talk", {})
            .get("botSecret", "")
        )
        if bot_secret:
            print(
                f"   ✅ Bot-Secret found in config.json ({len(bot_secret)} characters)"
            )

    # Test with placeholder
    bot_secret = "test-shared-secret-min-40-zeichen"
    random_value = os.urandom(32).hex()
    body = json.dumps(test_payload)
    signature = hmac.new(
        bot_secret.encode(),
        (random_value + body).encode(),
        hashlib.sha256,
    ).hexdigest()

    print(f"   RANDOM_VALUE: {random_value}")
    print(f"   SIGNATURE: {signature}")

    # Send test request
    print("\n🌐 Sending Test Request to:")
    url = f"http://localhost:{port}/webhook/nextcloud_talk"

    print(f"   URL: {url}")
    print(f"   HEADERS:")
    print(f"     X-Nextcloud-Talk-Random: {random_value}")
    print(f"     X-Nextcloud-Talk-Signature: {signature}")
    print(f"   BODY: {body[:100]}...")

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(
                url,
                content=body,
                headers={
                    "X-Nextcloud-Talk-Random": random_value,
                    "X-Nextcloud-Talk-Signature": signature,
                    "Content-Type": "application/json",
                },
            )
            print(f"\n✅ Response received:")
            print(f"   Status: {response.status_code}")
            print(f"   Body: {response.text[:200]}...")

            if response.status_code == 200:
                print("\n🎉 Webhook test successful!")
            else:
                print(f"\n❌ Webhook test failed! Status: {response.status_code}")

    except httpx.ConnectError:
        print("\n❌ Connection failed!")
        print(f"   Make sure the nanobot gateway is running on port {port}:")
        print(f"   > nanobot gateway")
    except Exception as e:
        print(f"\n❌ Error during request: {e}")


async def start_webhook_test_server() -> None:
    """Starts a local webhook server for testing."""
    print(f"🚀 Starting local Webhook Test Server")

    app = web.Application()

    async def handle_webhook(request):
        """Handle the webhook."""
        from aiohttp import web

        print(f"\n📨 Webhook received!")

        try:
            body_bytes = await request.read()
            body_str = body_bytes.decode("utf-8")

            random_header = request.headers.get("X-Nextcloud-Talk-Random", "")
            sig_header = request.headers.get("X-Nextcloud-Talk-Signature", "")

            print(f"   RANDOM_HEADER: {random_header}")
            print(f"   SIGNATURE_HEADER: {sig_header}")
            print(f"   BODY: {body_str[:200]}...")

            # Test bot secret
            bot_secret = "test-shared-secret-min-40-zeichen"

            expected = hmac.new(
                bot_secret.encode(),
                (random_header + body_str).encode(),
                hashlib.sha256,
            ).hexdigest()

            if not hmac.compare_digest(sig_header.lower(), expected.lower()):
                print(f"   ❌ Invalid signature!")
                return web.Response(status=401, text="Unauthorized")

            print(f"   ✅ Signature validated!")

            data = json.loads(body_str)
            print(f"   Event-Type: {data.get('type')}")

            response = {"status": 200, "text": "OK", "received_payload": data}

            print(f"   📦 Response: {json.dumps(response)[:200]}...")
            return web.json_response(response)

        except Exception as e:
            print(f"   ❌ Error: {e}")
            return web.Response(status=500, text=str(e))

    app.router.add_post("/webhook/nextcloud_talk", handle_webhook)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", 18791)
    await site.start()

    print(f"✅ Test server started at http://localhost:18791/webhook/nextcloud_talk")
    print("⚠️  Press CTRL+C to exit")

    try:
        while True:
            await asyncio.sleep(1)
    except asyncio.CancelledError:
        print("\n🛑 Server is shutting down...")
        await runner.cleanup()


async def main() -> None:
    """Main function."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Webhook Test Script for Nextcloud Talk Channel"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=18791,
        help="Port for webhook server (default: 18791)",
    )
    parser.add_argument(
        "--test-external",
        action="store_true",
        help="Test webhook on port 18790 (Gateway server)",
    )

    args = parser.parse_args()

    if args.test_external:
        # Test external gateway server
        await test_webhook(port=18790)
    else:
        # Start local test server
        await start_webhook_test_server()


if __name__ == "__main__":
    asyncio.run(main())
