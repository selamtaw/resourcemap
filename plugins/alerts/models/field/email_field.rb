class Field::EmailField < Field
  def value_type_description
    "email addresses"
  end

  def value_hint
    "Example of valid email: myemail@resourcemap.com."
  end

  def valid_value?(email_value, site=nil)
    check_email_format(email_value)
  end

	private

	def check_email_format(value)
    regex = Regexp.new('^(|(([A-Za-z0-9]+_+)|([A-Za-z0-9]+\-+)|([A-Za-z0-9]+\.+)|([A-Za-z0-9]+\++))*[A-Za-z0-9]+@((\w+\-+)|(\w+\.))*\w{1,63}\.[a-zA-Z]{2,6})$')
    if value.match(regex).nil?
      raise "Invalid email address in field #{code}"
    end
    true
  end

end
