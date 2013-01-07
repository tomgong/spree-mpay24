class MpayLogger < Logger
  
  LOGGING_PATH = 'log/mpay.log'
  
  def initialize
    super(LOGGING_PATH)
  end
  
  def format_message(severity, timestamp, progname, msg)
    "#{timestamp.to_formatted_s(:db)} #{severity} #{msg}\n" 
  end 
  
end