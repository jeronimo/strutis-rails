require 'rails_helper'

RSpec.describe 'conversations/_progress' do
  let(:conversation) { Conversation.new(public_id: 'progress-render-check') }

  it 'renders the retry alert with countdown when retry_status is present' do
    html = ApplicationController.render(partial: 'conversations/progress', locals: { conversation:, active: true, retry_status: { attempt: 4, max: 5, wait: 40 } })
    expect(html).to include('Retrying — attempt 4 of 5, next try in')
    expect(html).to include('retry-countdown')
    expect(html).to include('data-retry-countdown-seconds-value="40"')
  end

  it 'renders no alert when retry_status is absent' do
    html = ApplicationController.render(partial: 'conversations/progress', locals: { conversation:, active: true })
    expect(html).not_to include('Retrying')
    expect(html).not_to include('retry-countdown')
  end

  it 'renders hidden without alert when inactive' do
    html = ApplicationController.render(partial: 'conversations/progress', locals: { conversation:, active: false })
    expect(html).to include('d-none')
    expect(html).not_to include('Retrying')
  end
end
