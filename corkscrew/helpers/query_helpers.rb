module Corkscrew
  module Helpers
    module QueryHelpers

      def ask_default_yes(prompt)
        ask_boolean(prompt, default: true)
      end

      def ask_default_no(prompt)
        ask_boolean(prompt, default: false)
      end

      def ask_boolean(prompt, default: )
        loop do
          answer = ask(
            prompt,
            add_to_history: false
          )

          case answer
          when nil
            say ''
            return default
          when ''
            return default
          when /\A(yes|y)\z/i
            return true
          when /\A(no|n)\z/i
            return false
          else
            next
          end
        end
      end

      def ask_nonempty(prompt, opts={})
        loop do
          answer = ask(prompt, opts)
          next if answer.nil? || answer.strip.empty?

          return answer
        end
      end

    end
  end
end