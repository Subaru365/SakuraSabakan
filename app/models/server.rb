# encoding: utf-8

class Server < ActiveRecord::Base
  attr_accessible :address, :description

  # Relation Ship
  belongs_to :account

  has_many :ping_logs,
    dependent: :delete_all
  has_many :httping_logs,
    dependent: :delete_all

  # Validations
  validates :address,
    uniqueness: true,
    presence: true,
    length: {maximum: 30}
  validate :address_valid?

  validates :account_id,
    presence: true,
    numericality: :only_integer


  # pingの監視を実行
  def check_ping
    # ping実行
    ping_str = `ping -c 5 #{self.address}`
    # pingのログから情報を抽出
    parser = PingLogParser.new ping_str
    rtt = parser.parse_rtt
    stat = parser.parse_stat

    # ログに記録
    ping_log = self.ping_logs.new
    ping_log.attributes = rtt
    ping_log.attributes = stat
    ping_log.ping_detail = ping_str
    ping_log.status = (stat[:packet_loss] > 0.0 ? 'Failed' : 'Success')

    ping_log.save!
  end

  # 最近のpingの稼働率
  def recent_ping_rate(from)
    logs = self.ping_logs.recent(from)
    rate = logs.success.count.to_f / logs.count * 100
    rate.round 1
  end

  def ping_status_before(from)
    if self.ping_logs.recent(from).count == 0
      h = :no_log
    elsif self.ping_logs.recent(from).asc_by_date.last.status == 'Failed'
      h = :danger
    elsif self.ping_logs.failed.recent(1.hour).count != 0
      h = :waring
    else
      h = :success
    end

    return h
  end




  # httpの監視を実行
  def check_http
    # httping実行
    ping_str = `httping -s -c 5 #{self.address}`
    # httpingのログから情報を抽出
    parser = HttpingLogParser.new ping_str
    rtt = parser.parse_rtt
    stat = parser.parse_stat

    # ログに記録
    log = self.httping_logs.new
    log.attributes = rtt
    log.attributes = stat
    log.detail = ping_str
    log.status = parser.parse_status[:status]

    log.save!
  end

	# 最近1日間のHTTPの稼働率
  def recent_http_rate(from)
    logs = self.httping_logs.recent(from)
    rate = logs.success.count.to_f / logs.count * 100
    rate.round 1
  end

  def http_status_before(from)
    if self.httping_logs.recent(from).count == 0
      h = :no_log
    elsif self.httping_logs.recent(from).asc_by_date.last.status !~ /^[1-3].*$/
      h = :danger
    elsif self.httping_logs.failed.recent(1.hour).count != 0
      h = :waring
    else
      h = :success
    end

    return h
  end



  # 最近1日間サーバ（全サービス）の稼働率
  def recent_rate(from)
    service_rates = []
    service_rates << recent_ping_rate(from)
    service_rates << recent_http_rate(from)

    rate = service_rates.inject{|sum, i| sum + i } / service_rates.count
    rate.round 1
  end

  # 直前のログにエラーがいくつあるか
  def count_errors_just_before
    pings = self.ping_logs.recent(1.day).asc_by_date
    https = self.httping_logs.recent(1.day).asc_by_date
    res = []

    res << (pings.last.status == 'Failed') if pings.last
    res << (https.last.status !~ /^[1-3].*$/) if https.last

    return res.count{|i| i }
  end

  # 最近の全エラー数
  def count_errors_before(span)
    res = []
    res << self.ping_logs.recent(span).failed.count
    res << self.httping_logs.recent(span).failed.count

    return res.inject { |sum, i| sum + i }
  end

  # 監視ログがあるかどうか
  def count_logs
    res = []
    res << self.ping_logs.recent(1.day).count
    res << self.httping_logs.recent(1.day).count

    return res.inject { |sum, i| sum + i }
  end

  def status_before(from)
    if self.count_logs == 0
      # ログが無ければブルー
      alert = :no_log

    elsif self.count_errors_just_before != 0
      # 前回のログにエラーがある場合は警告
      alert = :danger

    elsif self.count_errors_before(1.hour) != 0
      # 過去1時間にエラーがあれば注意
      alert = :warning
    else
      # 何も無ければグリーン
      alert = :success
    end
  end

  private
  def address_valid?
    errors.add(:address, 'に不正な文字が含まれています。（日本語ドメインには非対応です）') unless self.address =~ /^[0-9A-Za-z\-.]+$/
  end
end
