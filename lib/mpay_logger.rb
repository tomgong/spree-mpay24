class MpayLogger < Logger
  
  LOGGING_PATH = 'log/mpay.log'
  
  def initialize
    super(LOGGING_PATH)
  end
  
  def format_message(severity, timestamp, progname, msg)
    "#{timestamp.to_formatted_s(:db)} #{severity} #{msg}\n" 
  end 
  
  def error(msg)
    super msg
    MpayMailer.mpay_error(msg).deliver
  end

  def fatal(msg)
    super msg
    MpayMailer.mpay_error(msg).deliver
  end
  
end