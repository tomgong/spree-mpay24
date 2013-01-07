require 'net/https'
require 'uri'

# Integrate our payment gateway with spree. This is needed
# to allow configuration through spree's web interface, etc.
class BillingIntegration::Mpay < BillingIntegration

  preference :production_merchant_id, :string
  preference :test_merchant_id, :string
  preference :url, :string
  preference :secret_phrase, :string
  preference :mpay24_ip, :string, :default => "213.164.25.245"
  preference :mpay24_test_ip, :string, :default => "213.164.23.169"

  def mpay_logger
    @@mpay_logger ||= MpayLogger.new
  end
    
  TEST_REDIRECT_URL = 'https://test.mPAY24.com/app/bin/etpv5'
  PRODUCTION_REDIRECT_URL = 'https://www.mpay24.com/app/bin/etpv5'

  def provider_class
    ActiveMerchant::Billing::MpayGateway
  end

  def self.current
    # I'm not sure why I'm needing RAILS_ENV.to_s. It looks like a string
    # but cannot otherwise be compared to another string
    BillingIntegration::Mpay.where(:active => true).where(:environment => RAILS_ENV.to_s).first
  end

  def verify_ip(request)

    if request_ip(request) != mpay24_ip
      mpay_logger.error "invalid forwarded originator IP #{request_ip(request)} vs #{mpay24_ip}"
      return false
    end
    
    return true
  end

  def find_order(tid)
    if prefers_secret_phrase?
      if tid.starts_with?(preferred_secret_phrase)
        tid = tid.gsub(/^#{preferred_secret_phrase}_/, "")
      else
        raise "unknown secret phrase: #{tid}".inspect
      end
    end

    Order.find(:first, :conditions => { :id => tid })
  end

  def gateway_url
    prefers_test_mode? ? TEST_REDIRECT_URL : PRODUCTION_REDIRECT_URL
  end

  def request_ip(request)
    request.ip
  end
  
  def mpay24_ip
    prefers_test_mode? ? preferred_mpay24_test_ip : preferred_mpay24_id
  end

  def merchant_id
    prefers_test_mode? ? preferred_test_merchant_id : preferred_production_merchant_id
  end

  # generate the iframe URL
  def generate_url(order)

    cmd = generate_mdxi(order)

    mpay_logger.debug "Order #{order.number}: Generated xml request doc: #{cmd}"
    
    # send the HTTP request
    mpay_logger.info "Order #{order.number}: Sending http request to #{gateway_url} and merchant id #{merchant_id}"
    response = send_request(merchant_id, cmd)

    result = parse_result(response)

    mpay_logger.debug "Order #{order.number}: Full response: #{response.body}"
    mpay_logger.info "Order #{order.number}: mpay returned result: #{result}"
    
    # if everything did work out: return the link url. Otherwise
    # output an ugly exception (at least we will get notified)
    if result["STATUS"] == "OK" && result["RETURNCODE"] == "REDIRECT"
      order.created_at = Time.now
      order.save!
      return result["LOCATION"].chomp
    else
      mpay_logger.error "Order #{order.number}: Response of mpay is not OK: #{response.body}"
      return '/mpay_error'
    end
  end

  private

  def parse_result(response)
    result = {}

    response.body.split('&').each do |part|
      key, value = part.split("=")
      result[key] = CGI.unescape(value) unless value.nil?
    end

    result
  end

  def generate_tid(order_id)
    if prefers_secret_phrase?
      "#{preferred_secret_phrase}_#{order_id}"
    else
      order_id
    end
  end

  def send_request(merchant_id, cmd)
  
    url = URI.parse(gateway_url)
    request = Net::HTTP::Post.new(url.path,{"Content-Type"=>"text/xml"})
    http = Net::HTTP.new(url.host, url.port)

    # verify through SSL
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER

    request = Net::HTTP::Post.new(url.request_uri)
    request.set_form_data({
                  'OPERATION' => 'SELECTPAYMENT',
                  'MERCHANTID' => merchant_id,
                  'MDXI' => cmd
    })

    http.request(request)
  end

  def generate_mdxi(order)
    tid = generate_tid(order.id)
    
    mpay_logger.info "Order #{order.number}: Starting mpay request (generate_mdxi) with TID #{tid}"
    
    xml = Builder::XmlMarkup.new
    xml.instruct! :xml, :version=>"1.0", :encoding=>"UTF-8"
    xml.tag! 'Order' do
      xml.tag! 'Tid', tid
      xml.tag! 'ShoppingCart' do
        xml.tag! 'Description', order.number

        order.line_items.each do |li|
          xml.tag! 'Item' do
            xml.tag! 'Description', li.variant.product.name
            xml.tag! 'Quantity', li.quantity
            xml.tag! 'ItemPrice', sprintf("%.2f", li.price)
          end
        end

        order.update_totals

        xml.tag! 'Tax', sprintf("%.2f", order.tax_total)

        # TODO is this the same as order.credit_total?
        discounts = order.adjustment_total - order.tax_total - order.ship_total

        xml.tag! 'Discount', sprintf("%.2f", discounts)

        xml.tag! 'ShippingCosts', sprintf("%.2f", order.ship_total)
      end

      xml.tag! 'Price', sprintf("%.2f", order.total)

      xml.tag! 'BillingAddr', :Mode => 'ReadWrite' do
        xml.tag! 'Name', "#{order.ship_address.firstname} #{order.ship_address.lastname}"
        xml.tag! 'Street', order.bill_address.address1
        xml.tag! 'Street2', order.bill_address.address2
        xml.tag! 'Zip', order.bill_address.zipcode
        xml.tag! 'City', order.bill_address.city
        xml.tag! 'State', order.bill_address.state_name
        xml.tag! 'Country', order.bill_address.country.name
        xml.tag! 'Email', order.email
      end

      xml.tag! 'ShippingAddr', :Mode => 'ReadOnly' do
        xml.tag! 'Name', "#{order.ship_address.firstname} #{order.ship_address.lastname}"
        xml.tag! 'Street', order.ship_address.address1
        xml.tag! 'Street2', order.ship_address.address2
        xml.tag! 'Zip', order.ship_address.zipcode
        xml.tag! 'City', order.ship_address.city
        xml.tag! 'State', order.ship_address.state_name
        xml.tag! 'Country', order.ship_address.country.name
        xml.tag! 'Email', order.email
      end
      xml.tag! 'URL' do
        xml.tag! 'Success', "#{preferred_url}/mpay_callbacks"
        xml.tag! 'Confirmation', "#{preferred_url}/mpay_confirmation"
      end
    end

    xml.target!
  end
end
