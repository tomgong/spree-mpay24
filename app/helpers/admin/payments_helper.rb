module Admin::PaymentsHelper
  def payment_method_name(payment)
    # hack to allow us to retrieve the name of a "deleted" payment method
    id = payment.payment_method_id

    # hack because the payment method is not set in the mpay confirmation controller. fix it
    if id == nil then
      method = BillingIntegration::Mpay.where(:active => true).where(:environment => Rails.env.to_s)
    else
      # TODO: include destroyed payment methods
      method = PaymentMethod.find_by_id(id)

      # somehow we've got invalid payment methods in our system
      method = BillingIntegration::Mpay.where(:active => true).where(:environment => Rails.env.to_s).first if method.nil?      
    end
    
    if method.nil?
      'unknown'
    else
      method.name
    end
    
  end
end
