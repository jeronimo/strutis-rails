require 'rails_helper'

RSpec.describe OpenaiService do
  before do
    allow(described_class).to receive(:credentials).and_return({ host: 'localhost', port: 8080, key: 'test-key', open_timeout: 5, read_timeout: 30 })
    described_class.instance_variable_set(:@models, nil)
    described_class.instance_variable_set(:@models_fetched_at, nil)
  end

  let(:tools) { [ { function: { name: 'web-search', parameters: { type: 'object' } }, endpoint: 'http://tools.local/search' } ] }
  let(:tool_call) { { id: 'call_1', type: 'function', function: { name: 'web-search', arguments: '{"query":"x"}' } } }

  def sse(*events)
    events.map { |event| event == '[DONE]' ? 'data: [DONE]' : "data: #{event.to_json}" }.join("\n\n") + "\n\n"
  end

  describe '#execute_tool' do
    it 'sends the tool arguments as a JSON object body, not a JSON string' do
      stub_request(:post, 'http://tools.local/search')
        .with(body: '{"query":"x"}')
        .to_return(status: 200, body: '{"result":"ok"}')

      result = described_class.new.execute_tool(tool_call, tools)

      expect(result).to eq('{"result":"ok"}')
      expect(a_request(:post, 'http://tools.local/search').with(body: '{"query":"x"}')).to have_been_made
    end

    it 'sends authorization and context headers on the tool endpoint' do
      stub_request(:post, 'http://tools.local/search').to_return(status: 200, body: 'ok')

      described_class.new(conversation_id: 'conv-1', user_public_id: 'user-1').execute_tool(tool_call, tools)

      expect(a_request(:post, 'http://tools.local/search').with(headers: {
        'Authorization' => 'Bearer test-key', 'Content-Type' => 'application/json',
        'X-Conversation-Id' => 'conv-1', 'X-User-Public-Id' => 'user-1'
      })).to have_been_made
    end

    it 'appends -dev to X-User-Public-Id in development' do
      allow(Rails.env).to receive(:development?).and_return(true)
      stub_request(:post, 'http://tools.local/search').to_return(status: 200, body: 'ok')

      described_class.new(conversation_id: 'conv-1', user_public_id: 'user-1').execute_tool(tool_call, tools)

      expect(a_request(:post, 'http://tools.local/search')
        .with(headers: { 'X-User-Public-Id' => 'user-1-dev' })).to have_been_made
    end

    it 'omits context headers when no context is set' do
      stub_request(:post, 'http://tools.local/search').to_return(status: 200, body: 'ok')

      described_class.new.execute_tool(tool_call, tools)

      expect(a_request(:post, 'http://tools.local/search').with { |request|
        request.headers['Authorization'] == 'Bearer test-key' &&
          !request.headers.key?('X-Conversation-Id') && !request.headers.key?('X-User-Public-Id')
      }).to have_been_made
    end

    it 'returns an unknown tool message without sending a request' do
      result = described_class.new.execute_tool({ id: 'c', type: 'function', function: { name: 'missing', arguments: '{}' } }, tools)

      expect(result).to eq('Unknown tool: missing. Allowed tools: web-search.')
      expect(a_request(:post, 'http://tools.local/search')).not_to have_been_made
    end

    it 'returns the error body on a non-success response' do
      stub_request(:post, 'http://tools.local/search').to_return(status: 422, body: '{"detail":"bad"}')

      expect(described_class.new.execute_tool(tool_call, tools)).to eq('{"detail":"bad"}')
    end

    it 'returns a timeout message on Net::OpenTimeout' do
      stub_request(:post, 'http://tools.local/search').to_raise(Net::OpenTimeout)

      expect(described_class.new.execute_tool(tool_call, tools)).to eq('Tool error (web-search): request timed out after 5s')
    end
  end

  describe '#completion' do
    it 'sends the prompt body with conversation context and normalized tools' do
      stub_request(:post, 'http://localhost:8080/v1/chat/completions')
        .to_return(status: 200, headers: { 'Content-Type' => 'text/event-stream' }, body: sse('[DONE]'))

      described_class.new(conversation_id: 'conv-1', user_public_id: 'user-1').completion(
        [ { role: 'user', content: 'hi' } ], 'test-model', tools: tools, chat_template_kwargs: { enable_thinking: false }
      )

      expect(a_request(:post, 'http://localhost:8080/v1/chat/completions').with(headers: {
        'X-Conversation-Id' => 'conv-1', 'X-User-Public-Id' => 'user-1'
      })).to have_been_made
      expect(a_request(:post, 'http://localhost:8080/v1/chat/completions').with { |request|
        body = JSON.parse(request.body)
        body['model'] == 'test-model' &&
          body['stream'] == true &&
          body['stream_options'] == { 'include_usage' => true } &&
          body['conversation_id'] == 'conv-1' &&
          body['chat_template_kwargs'] == { 'enable_thinking' => false } &&
          body['tools'] == [ { 'function' => { 'name' => 'web-search', 'parameters' => { 'type' => 'object' }, 'strict' => true } } ]
      }).to have_been_made
    end

    it 'accumulates streamed content, yields deltas, and collects usage' do
      stub_request(:post, 'http://localhost:8080/v1/chat/completions')
        .to_return(status: 200, headers: { 'Content-Type' => 'text/event-stream' }, body: sse(
          { choices: [ { delta: { content: 'hel' } } ] },
          { choices: [ { delta: { content: 'lo' } } ], usage: { prompt_tokens: 10, completion_tokens: 2 } },
          '[DONE]'
        ))
      deltas = []

      result = described_class.new.completion([ { role: 'user', content: 'hi' } ], 'test-model') { |delta| deltas << delta }

      expect(result[:content]).to eq('hello')
      expect(deltas).to eq([ 'hel', 'lo' ])
      expect(result[:prompt_tokens]).to eq(10)
      expect(result[:completion_tokens]).to eq(2)
      expect(result[:stopped]).to be false
    end

    it 'accumulates streamed tool call fragments' do
      stub_request(:post, 'http://localhost:8080/v1/chat/completions')
        .to_return(status: 200, headers: { 'Content-Type' => 'text/event-stream' }, body: sse(
          { choices: [ { delta: { tool_calls: [ { index: 0, id: 'call_1', type: 'function', function: { name: 'web-search', arguments: '{"que' } } ] } } ] },
          { choices: [ { delta: { tool_calls: [ { index: 0, function: { arguments: 'ry":"x"}' } } ] } } ] },
          '[DONE]'
        ))

      result = described_class.new.completion([ { role: 'user', content: 'hi' } ], 'test-model')

      expect(result[:tool_calls]).to eq([ { id: 'call_1', type: 'function', function: { name: 'web-search', arguments: '{"query":"x"}' } } ])
    end

    it 'stops without content when should_stop is already true' do
      stub_request(:post, 'http://localhost:8080/v1/chat/completions')
        .to_return(status: 200, headers: { 'Content-Type' => 'text/event-stream' }, body: sse({ choices: [ { delta: { content: 'partial' } } ] }, '[DONE]'))

      result = described_class.new.completion([ { role: 'user', content: 'hi' } ], 'test-model', should_stop: -> { true })

      expect(result[:stopped]).to be true
      expect(result[:content]).to eq('')
    end

    it 'raises with the error detail on a non-success response' do
      stub_request(:post, 'http://localhost:8080/v1/chat/completions').to_return(status: 500, body: '{"error":{"message":"boom"}}')

      expect { described_class.new.completion([ { role: 'user', content: 'hi' } ], 'test-model') }.to raise_error(OpenaiService::Error, /boom/)
    end
  end

  describe '#tools' do
    it 'returns the tools data' do
      stub_request(:get, 'http://localhost:8080/v1/tools').to_return(status: 200, body: '{"data":[{"function":{"name":"web-search"},"endpoint":"http://tools.local/search"}]}')

      expect(described_class.new.tools).to eq([ { function: { name: 'web-search' }, endpoint: 'http://tools.local/search' } ])
    end

    it 'raises with the error detail on a non-success response' do
      stub_request(:get, 'http://localhost:8080/v1/tools').to_return(status: 500, body: '{"error":{"message":"boom"}}')

      expect { described_class.new.tools }.to raise_error(OpenaiService::Error, /boom/)
    end
  end

  describe '.models' do
    it 'fetches and caches the model list' do
      stub_request(:get, 'http://localhost:8080/v1/models').to_return(status: 200, body: '{"data":[{"id":"m1","context_length":100}]}')

      expect(described_class.models).to eq([ { id: 'm1', context_length: 100 } ])
      expect(described_class.models).to eq([ { id: 'm1', context_length: 100 } ])
      expect(a_request(:get, 'http://localhost:8080/v1/models')).to have_been_made.once
    end

    it 'looks up model metadata' do
      stub_request(:get, 'http://localhost:8080/v1/models').to_return(status: 200, body: '{"data":[{"id":"m1","context_length":100,"chat_template_kwargs":{"enable_thinking":true}}]}')

      expect(described_class.context_length('m1')).to eq(100)
      expect(described_class.chat_template_kwargs('m1')).to eq({ enable_thinking: true })
      expect(described_class.context_length('missing')).to be_nil
    end

    it 'reports image input support from model capabilities' do
      stub_request(:get, 'http://localhost:8080/v1/models').to_return(status: 200, body: '{"data":[{"id":"m1","capabilities":{"input":["text","image"]}},{"id":"m2","capabilities":{"input":["text"]}}]}')

      expect(described_class.supports_image_input?('m1')).to be true
      expect(described_class.supports_image_input?('m2')).to be false
      expect(described_class.supports_image_input?('missing')).to be false
    end

    it 'reports text and audio input support from model capabilities' do
      stub_request(:get, 'http://localhost:8080/v1/models').to_return(status: 200, body: '{"data":[{"id":"m1","capabilities":{"input":["text","image"]}},{"id":"m2","capabilities":{"input":["audio"]}}]}')

      expect(described_class.supports_text_input?('m1')).to be true
      expect(described_class.supports_text_input?('m2')).to be false
      expect(described_class.supports_stt?('m1')).to be false
      expect(described_class.supports_stt?('m2')).to be true
    end

    it 'finds the stt model by audio input capability' do
      stub_request(:get, 'http://localhost:8080/v1/models').to_return(status: 200, body: '{"data":[{"id":"m1","capabilities":{"input":["text"]}},{"id":"m2","capabilities":{"input":["audio"]}}]}')

      expect(described_class.stt_model[:id]).to eq('m2')
    end
  end

  describe '#transcribe' do
    def audio_file
      tempfile = Tempfile.new('recording')
      tempfile.write('audio-bytes')
      tempfile.rewind
      ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: 'recording.webm', content_type: 'audio/webm')
    end

    it 'sends multipart/form-data with file and model fields' do
      stub_request(:post, 'http://localhost:8080/v1/audio/transcriptions').to_return(status: 200, body: '{"text":"hello world"}')

      expect(described_class.new.transcribe(audio_file, 'stt-model')).to eq('hello world')

      expect(a_request(:post, 'http://localhost:8080/v1/audio/transcriptions') do |req|
        req.headers['Content-Type'].start_with?('multipart/form-data; boundary=') &&
          req.body.include?('name="model"') &&
          req.body.include?('stt-model') &&
          req.body.include?('name="file"; filename="recording.webm"') &&
          req.body.include?('Content-Type: audio/webm') &&
          req.body.include?('audio-bytes')
      end).to have_been_made
    end

    it 'raises an error on a non-success response' do
      stub_request(:post, 'http://localhost:8080/v1/audio/transcriptions').to_return(status: 500, body: '{"error":{"message":"boom"}}')

      expect { described_class.new.transcribe(audio_file, 'stt-model') }.to raise_error(OpenaiService::Error, /boom/)
    end
  end
end
