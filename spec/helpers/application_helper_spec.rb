require 'rails_helper'

RSpec.describe ApplicationHelper do
  include ApplicationHelper
  include ActionView::Helpers::SanitizeHelper

  let(:original) do
    <<~TEXT
      Llama 4 Scout Instruct is best for:

      1. **Multimodal understanding**: It is optimized for both text and image inputs.
      2. **Long-document tasks**: It has a 10M token context window.

      Some of the key features of Llama 4 Scout Instruct include:

      * 17 billion parameter model with 16 experts
      * Mixture-of-experts architecture
      * 10M token context window
      * Multimodal capabilities (text and image inputs)
      * Multilingual support
      * Optimized for coding and tool-calling

      It is available on various platforms.
    TEXT
  end

  describe '#render_message_markdown' do
    it 'reproduces the stripped response (whitespace dropped around digits and list markers)' do
      html = render_message_markdown(original)
      text = html.gsub(/<[^>]+>/, '')

      puts "=== HTML ==="
      puts html
      puts "=== TEXT (tags stripped) ==="
      puts text

      expect(text).to include('Llama4')
      expect(text).to include('a10M')
      expect(text).to include('with16')
      expect(text).to include('*17')
    end
  end
end
