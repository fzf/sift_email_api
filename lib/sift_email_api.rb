require 'net/http'
require 'openssl'
require 'json'
require 'uri'
require 'connection_pool'

class SiftEmailApi
	# @private
	@@api_endpoint='api.easilydo.com'
	# @private
	@@conn_pool = ConnectionPool.new(size: 20, timeout: 30) do
		http = Net::HTTP.new(@@api_endpoint, 443)
		http.use_ssl=true
		http
	end

	# Sole constructor
	#
	# @param api_key [String]	sift developer's api key
	# @param secret_key [String]	sift developer's secret key
	def initialize(api_key, secret_key)
		@api_key=api_key
		@secret_key=secret_key
	end

	# Get a list of sifts for the given user
	def get_token(username)
		path = '/v1/connect_token'
		params = {'username' => username}

		add_common_params('POST', path, params)

		request = Net::HTTP::Post.new path
		request.set_form_data params

		execute_request(request)
	end

	#
	# @param username [String]	username of the user to fetch sifts for
	# @param last_update_time [Time]	only return sifts updated since this date
	# @param offset	[Integer] used for paging, where to start
	# @param limit [Integer] maximum number of results to return
	# @param domains [Array] list of domain strings. If provided, only sifts in the specified domains will be returned
	# @return [Array] list of sifts in descending order of last update time, available fields documented here: {https://developer.easilydo.com/sift/documentation#flights}
	def list_sifts(username, last_update_time=nil, offset=nil, limit=nil, domains=nil)
		path = '/v1/users/%s/sifts' % username
		params = {}

		if last_update_time
			params['last_update_time'] = last_update_time.to_i()
		end

		if offset
			params['offset'] = offset
		end

		if limit
			params['limit'] = limit
		end

		if domains and not domains.empty?
			params['domains'] = domains.join(',')
		end

		add_common_params('GET', path, params)

		uri = URI::HTTPS.build({:host => @@api_endpoint, :path => path, :query => URI.encode_www_form(params)})
		request = Net::HTTP::Get.new uri

		execute_request(request)
	end

	# Get a particular sift
	#
	# @param username [String]	username of the user to fetch sifts for
	# @param sift_id [Integer]	numeric id of the sift to be fetched
	# @return [Hash]	the sift corresponding to the provided id, available fields (by domain) documented here: {https://developer.easilydo.com/sift/documentation#flights}
	def get_sift(username, sift_id)
		path = '/v1/users/%s/sifts/%d' % [username, sift_id]
		params = {}

		add_common_params('GET', path, params)

		uri = URI::HTTPS.build({:host => @@api_endpoint, :path => path, :query => URI.encode_www_form(params)})
		request = Net::HTTP::Get.new uri

		execute_request(request)
	end

	# Register a new user
	#
	# @param username [String]	username of the new user
	# @param locale [String]	locale of the new user
	# @return [Integer]	the numeric user id of the newly created user
	def add_user(username, locale)
		path = '/v1/users'
		params = {'username' => username, 'locale' => locale}

		add_common_params('POST', path, params)

		request = Net::HTTP::Post.new path
		request.set_form_data params

		execute_request(request)
	end

	# Deletes a user
	#
	# @param username [String]	username of the user to delete
	def delete_user(username)
		path = '/v1/users/%s' % username
		params = {}

		add_common_params('DELETE', path, params)

		request = Net::HTTP::Delete.new path
		request.set_form_data params

		execute_request(request)
	end

	# List a user's email connections
	#
	# @param username [String]	username of the new user
	# @return [Array]	the list of the user's connections
	def list_connections(username, offset=nil, limit=nil)
		path = '/v1/users/%s/email_connections' % username
		params = {}

		if offset
			params['offset'] = offset
		end

		if limit
			params['limit'] = limit
		end

		add_common_params('GET', path, params)

		uri = URI::HTTPS.build({:host => @@api_endpoint, :path => path, :query => URI.encode_www_form(params)})
		request = Net::HTTP::Get.new uri

		execute_request(request)
	end

	# Add a Gmail connection to the given user account
	#
	# @param username [String]	username of the user
	# @param account [String]	email address
	# @param refresh_token [String]	oauth refresh token of the account
	# @return [Integer]	a generated numeric id for the connection
	def add_gmail_connection(username, account, refresh_token)
		credentials = {'refresh_token' => refresh_token}
		add_email_connection(username, account, 'google', credentials)
	end

	# Add a Yahoo connection to the given user account
	#
	# @param username [String]	username of the user
	# @param account [String]	email address
	# @param refresh_token [String]	oauth refresh token of the account
	# @param redirect_uri [String]	redirect uri of the account
	# @return [Integer]	a generated numeric id for the connection
	def add_yahoo_connection(username, account, refresh_token, redirect_uri)
		credentials = {'refresh_token' => refresh_token, 'redirect_uri' => redirect_uri}
		add_email_connection(username, account, 'yahoo', credentials)
	end

	# Add a Microsoft Live connection to the given user account
	#
	# @param username [String]	username of the user
	# @param account [String]	email address
	# @param refresh_token [String]	oauth refresh token of the account
	# @param redirect_uri [String]	redirect uri of the account
	# @return [Integer] 	a generated numeric id for the connection
	def add_live_connection(username, account, refresh_token, redirect_uri)
		credentials = {'refresh_token' => refresh_token, 'redirect_uri' => redirect_uri}
		add_email_connection(username, account, 'live', credentials)
	end

	# Add an imap connection to the given user account
	# @param username [String]	username of the user
	# @param account [String]	email address
	# @param password [String]	password for the email account
	# @param host [String]	imap host to connect to
	# @return [Integer] 	a generated numeric id for the connection
	def add_imap_connection(username, account, password, host)
		credentials = {'password' => password, 'host' => host}
		add_email_connection(username, account, 'imap', credentials)
	end

	# Add a Microsoft Exchange connection to the given user account.
	# Sift will attempt to autodiscover the host and account name
	#
	# @param username [String]	username of the user
	# @param email [String]	email address
	# @param password [String]	password for the email account
	# @return [Integer] 	a generated numeric id for the connection
	def add_exchange_connection(username, email, password, account, host=nil)
		credentials = {'email' => email, 'password' => password}

		if host
			credentials['host'] = host
		end

		add_email_connection(username, account, 'exchange', credentials)
	end

	def add_email_connection(username, account, type, credentials)
		path = '/v1/users/%s/email_connections' % username
		params = credentials.clone()
		params['account_type'] = type
		params['account'] = account

		add_common_params('POST', path, params)

		request = Net::HTTP::Post.new path
		request.set_form_data params

		execute_request(request)
	end

	# Deletes an email connection
	#
	# @param username [String]	username of the user to delete
	# @param conn_id [Integer]	numeric id of the email connection
	def delete_connection(username, conn_id)
		path = '/v1/users/%s/email_connections/%d' % [username, conn_id]
		params = {}

		add_common_params('DELETE', path, params)

		request = Net::HTTP::Delete.new path
		request.set_form_data params

		execute_request(request)
	end

	# Extracts available domain data from the provided eml file.
	#
	# @param eml_str [String]	the eml file
	# @return [Array] 	list of sifts objects with extracted data
	def discovery(eml_str)
		path = '/v1/discovery'
		params = {'email' => eml_str.strip}

		add_common_params('POST', path, params)

		request = Net::HTTP::Post.new path
		request.set_form_data params

		execute_request(request)
	end

	# Get connect token for user
	#
	# @param username [String]	username of the new user
	# @return [Integer]	the numeric user id of the newly created user
	def connect_token(username)
		path = '/v1/connect_token'
		params = {'username' => username}

		add_common_params('POST', path, params)

		request = Net::HTTP::Post.new path
		request.set_form_data params

		execute_request(request)
	end

	# Get connect email url
	#
	# @param username [String]	username of the new user
	# @param connect_token [String]	token from connect token method
	# @return [Integer]	the numeric user id of the newly created user
	def connect_email_url(username, connect_token, callback_url)
		"https://api.edison.tech/v1/connect_email?" \
			"api_key=#{@api_key}&" \
			"username=#{username}&" \
			"token=#{connect_token}"
	end

	# Used to notify the Sift development team of emails that were not parsed correctly
	#
	# @param eml_str [String]	the eml file
	# @param locale [String]	locale of the email
	# @param timezone [String]	timezone of the email
	# @return [Hash] 	contains 2 boolean entries: "classfied" and "extracted"
	def feedback(eml_str, locale, timezone)
		path = '/v1/feedback'
		params = {'email' => eml_str.strip, 'locale' => locale, 'timezone' => timezone}

		add_common_params('POST', path, params)

		request = Net::HTTP::Post.new path
		request.set_form_data params

		execute_request(request)
	end

	def execute_request(request)
		response = @@conn_pool.with do |conn|
			conn.request(request)
		end

		#response = Net::HTTP.start(@@api_endpoint, 443, :use_ssl => true) do |http|
		#	http.request(req)
		#end

		case response
		when Net::HTTPClientError, Net::HTTPServerError
			msg = 'Sift API call failed ' + response.inspect()
			#$logger.error(msg)
			raise msg
		end

		root = JSON.parse(response.body)

		code = root['code'].to_i()

		if code >= 400
			msg = "Json response error from sift server. requestId: #{root['id']}, code: #{code}, msg :#{root['message']}}"
			raise msg
		end

		root['result']
	end

	def add_common_params(method, path, params)
		params['api_key'] = @api_key
		params['timestamp'] = Time.now.to_i.to_s
		params['signature'] = get_signature(method, path, params)
	end

	def get_signature(method, path, params)
		base = "#{method}&#{path}"
		params.keys.sort.each { |name|
			base << "&#{name}=#{params[name]}"
		}

		OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA1.new, @secret_key.encode('utf-8'), base.encode('utf-8'))
	end

	protected :add_common_params, :execute_request, :add_email_connection
	private :get_signature
end

