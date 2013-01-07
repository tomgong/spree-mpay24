class MpayMailer < ActionMailer::Base
  helper "spree/base"

  def mpay_error(errortext)
    @errortext = errortext
    subject = "MPAY ERROR"
    mail(:to => "office@starseeders.net",
         :subject => subject)
  end

end
