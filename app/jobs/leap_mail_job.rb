# Sends one LEAP approval mail through krai. Runs in the app process (:async)
# so it works without a separate job worker; a failed mail is only logged and
# never affects the submission or approval.
class LeapMailJob < ApplicationJob
  self.queue_adapter = :async unless Rails.env.test?

  def perform(kind, params)
    LeapMailRelay.deliver!(kind, params)
  rescue StandardError => error
    Rails.logger.error("LeapMailRelay failed kind=#{kind} to=#{params['to_email']}: #{error.class} #{error.message}")
  end
end
