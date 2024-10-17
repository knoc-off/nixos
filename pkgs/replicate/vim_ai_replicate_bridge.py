import os
from flask import Flask, request, Response, stream_with_context
import replicate

app = Flask(__name__)

@app.route('/complete', methods=['POST'])
def complete():
    data = request.json
    prompt = data.get('prompt', '')
    max_tokens = data.get('max_tokens', 1024)
    model = data.get('model', 'meta/meta-llama-3.1-405b-instruct')

    def generate():
        try:
            for event in replicate.stream(
                model,
                input={
                    "prompt": prompt,
                    "max_tokens": max_tokens
                }
            ):
                if hasattr(event, 'data') and event.data:
                    yield event.data.encode('utf-8')
        except Exception as e:
            app.logger.error(f"Error during replication stream: {e}")
            yield b""

    return Response(stream_with_context(generate()), content_type='text/plain; charset=utf-8')

def main():
    port = int(os.getenv('PORT', 5000))
    app.run(host='0.0.0.0', port=port)

if __name__ == '__main__':
    main()
