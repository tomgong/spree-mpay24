class MpayConfirmationController < Spree::BaseController

  # possible transaction states
  TRANSACTION_STATES = ["ERROR", "RESERVED", "BILLED", "REVERSED", "CREDITED", "SUSPENDED"]

  # Confirmation interface is a GET request
  def show

    unless BillingIntegration::Mpay.current.verify_ip(request) then
      render :text => "IP CHECK FAILED", :status => 401
    else

      check_operation(params["OPERATION"])
      check_status(params["STATUS"])

      # get the order
      order = BillingIntegration::Mpay.current.find_order(params["TID"])

      mpay_logger.debug "Order #{order.number}: Payment response from mpay with params: #{params}"

      case params["STATUS"]
      when "BILLED"
        
        # check if the retrieved order is the same as the outgoing one
        if verify_currency(order, params["CURRENCY"])

          # create new payment object
          payment_details = MPaySource.create ({
            :p_type => params["P_TYPE"],
            :brand => params["BRAND"],
            :mpayid => params["MPAYTID"]
  	      })
  	      
          payment_details.save!
          mpay_logger.info "Order #{order.number}: MPaySource(p_type = #{payment_details.p_type}, brand = #{payment_details.brand}, mpayid = #{payment_details.mpayid}) created"

          payment_method = PaymentMethod.where(:type => "BillingIntegration::Mpay").where(:environment => RAILS_ENV.to_s).first

          payment = order.payments.create({
            :amount => params["PRICE"],
            :payment_method_id => payment_method,
            :source => payment_details
  	      })
  	      
  	      mpay_logger.info "Order #{order.number}: Payment(amount = #{payment.amount}, payment_method_id = #{payment.payment_method_id}, source = #{payment.source}) created"

          # TODO: create this before (when sending the request?)
  	      # TODO: but do we even want this?
          payment.started_processing!
          payment.complete!
          payment.save!

          payment_details.payment = payment
          payment_details.save!
          order.update!
          order.next!
          
          mpay_logger.info "Order #{order.number}: Successfully created Payment. Sending 200 to mpay."
        end
        
      when "RESERVED"
  	    mpay_logger.info "Order #{order.number}: We have auto-completion for confirmation requests, so do nothing"
      else
        mpay_logger.error "Order #{order.number}: Unknown state: #{params["STATUS"]}"
        render :text => "UNKNOWN STATE", :status => 500
        return
      end

      render :text => "OK", :status => 200
    end
  end

  private

  def check_operation(operation)
    if operation != "CONFIRMATION"
      raise "unknown operation: #{operation}".inspect
    end
  end

  def check_status(status)
    if !TRANSACTION_STATES.include?(status)
      raise "unknown status: #{status}".inspect
    end
  end

  def find_order(tid)
    if (order = Order.find(tid)).nil?
      raise "could not find order: #{tid}".inspect
    end

    return order
  end

  def verify_currency(order, currency)
    "EUR" == currency
  end
  
  def mpay_logger
    @@mpay_logger ||= MpayLogger.new
  end
end
