require 'rails_helper'

RSpec.describe User, type: :model do
  let(:user) { User.create!(email: 'two-factor-user@example.com', password: 'password123') }

  describe '#issue_two_factor_code!' do
    it 'stores a pending code and enqueues the code email' do
      perform_enqueued_jobs do
        user.issue_two_factor_code!
      end

      expect(user.reload.two_factor_code_pending?).to be(true)
      expect(last_email_code).to be_present
    end

    it 'replaces a previous pending code' do
      user.issue_two_factor_code!
      first_digest = user.two_factor_code_digest
      user.issue_two_factor_code!
      expect(user.two_factor_code_digest).not_to eq(first_digest)
    end
  end

  describe '#consume_two_factor_code' do
    it 'consumes a valid code' do
      perform_enqueued_jobs { user.issue_two_factor_code! }
      code = last_email_code

      expect(user.consume_two_factor_code(code)).to be(true)
      expect(user.reload.two_factor_code_pending?).to be(false)
    end

    it 'rejects an invalid code' do
      perform_enqueued_jobs { user.issue_two_factor_code! }
      code = format('%06d', (last_email_code.to_i + 1) % 1_000_000)

      expect(user.consume_two_factor_code(code)).to be(false)
      expect(user.reload.two_factor_code_pending?).to be(true)
    end

    it 'rejects a consumed code' do
      perform_enqueued_jobs { user.issue_two_factor_code! }
      code = last_email_code
      user.consume_two_factor_code(code)

      expect(user.reload.consume_two_factor_code(code)).to be(false)
    end

    it 'rejects an expired code' do
      perform_enqueued_jobs { user.issue_two_factor_code! }
      code = last_email_code
      user.update!(two_factor_code_sent_at: User::TWO_FACTOR_CODE_EXPIRY.ago)

      expect(user.reload.consume_two_factor_code(code)).to be(false)
    end
  end
end
