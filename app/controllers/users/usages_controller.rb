module Users
  class UsagesController < Users::ApplicationController
    def show
      @usage = current_user.usage_by_model.to_a.map do |row|
        {
          name: OpenAiService.display_name(row.model),
          requests: row.requests.to_i,
          input: row.prompt_tokens.to_i,
          output: row.completion_tokens.to_i,
          thinking: row.reasoning_tokens.to_i,
          total: row.prompt_tokens.to_i + row.completion_tokens.to_i
        }
      end
      @totals = {
        requests: @usage.sum { |row| row[:requests] },
        input: @usage.sum { |row| row[:input] },
        output: @usage.sum { |row| row[:output] },
        thinking: @usage.sum { |row| row[:thinking] },
        total: @usage.sum { |row| row[:total] }
      }
    end
  end
end
