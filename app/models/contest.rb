class Contest < ActiveRecord::Base
  include PermissionsPolicy

  MinimumAnimes = 5
  MaximumAnimes = 128

  belongs_to :user

  attr_accessible :title, :description, :started_on, :phases, :votes_per_round, :vote_duration, :vote_interval, :user_vote_key

  validates_presence_of :title, :description, :user_id, :started_on, :user_vote_key
  validates_presence_of :vote_interval, :vote_duration, :votes_per_round, :numericality => { :greater_than => 0 }

  has_many :links, :class_name => ContestLink.name,
                   :dependent => :destroy

  has_many :animes, :through => :links,
                    :source => :linked,
                    :source_type => Anime.name,
                    :order => :name

  has_many :rounds, :class_name => ContestRound.name,
                    :order => [:number, :additional],
                    :dependent => :destroy

  has_one :thread, :class_name => ContestComment.name,
                    :foreign_key => :linked_id,
                    :conditions => { :linked_type => self.name },
                    :dependent => :destroy

  before_save :update_permalink
  after_save :update_thread_title

  state_machine :state, :initial => :created do
    state :created do
      # подготовка голосования к запуску
      def prepare
        rounds.destroy_all
        build_rounds
        fill_rounds
        update_attribute :updated_at, DateTime.now
      end
    end
    state :started
    state :finished do
      # результаты голосования
      def results
        rounds.includes(votes: [left: [:studios, :genres], right: [:studios, :genres]]).reverse.map do |round|
          items = round.votes.map do |vote|
            if vote.group == ContestRound::F
              [ vote.winner, vote.loser ]
            elsif vote.group == ContestRound::W
              [ ]
            else
              [ vote.loser ]
            end
          end.compact.flatten

          if round.votes.first.group == ContestRound::F
            items
          else
            items.compact.sort_by { |v| -v.score }
          end
        end.flatten.take animes.size
      end
    end

    event :start do
      transition :created => :started, :if => lambda { |contest| contest.links.count >= MinimumAnimes && contest.links.count <= MaximumAnimes } # && Contest.all.none?(&:started?)
    end
    event :finish do
      transition :started => :finished
    end

    before_transition :created => :started do |contest, transition|
      contest.update_attribute :started_on, Date.today if contest.started_on < Date.today
      if contest.rounds.empty? || contest.rounds.any? { |v| v.votes.any? { |v| v.started_on < Date.today } }
        contest.prepare
      end
    end
    after_transition :created => :started do |contest, transition|
      contest.send :create_comment_entry unless contest.thread
      contest.rounds.first.start!
    end
    after_transition :started => :finished do |contest, transition|
      contest.update_attribute :finished_on, Date.today
      User.update_all contest.user_vote_key => false
    end
  end

  # текущий раунд
  def current_round
    if finished?
      rounds.last
    else
      rounds.select(&:started?).first || rounds.select { |v| !v.finished? }.first || rounds.first
    end
  end

  # наступил следующий день. обновление состояний голосований
  def process!
    started = current_round.votes.select(&:can_start?).each(&:start!)
    finished = current_round.votes.select(&:can_finish?).each(&:finish!)
    round = if current_round.can_finish?
      current_round.finish!
    end

    update_attribute :updated_at, DateTime.now if started.any? || finished.any? || round
    #finish! if rounds.all?(&:finished?)
  end

  # побежденные аниме данным аниме
  def defeated_by(entry)
    @defeated ||= {}
    @defeated[entry.id] ||= ContestVote
        .where(contest_round_id: rounds.map(&:id))
        .where(state: 'finished')
        .where(winner_id: entry.id)
        .includes(:left, :right)
        .map { |vote|
          if vote.winner_id == vote.left_id
            vote.right
          else
            vote.left
          end
        }.compact
  end

  # для урлов
  def to_param
    "#{self.id}-#{self.permalink}"
  end

  # для совместимости с форумом
  def name
    title
  end

  class << self
    # текущий опрос
    def current
      Contest.where { state.eq('started') | (state.eq('finished') & finished_on.gte(DateTime.now - 1.week)) }
          .order(:started_on)
          .all
    end
  end

  # ключ в модели пользователя для хранении статуса проголосованности опроса
  def user_vote_key
    case self[:user_vote_key].to_s
      when 'can_vote_1' then 'can_vote_1'
      when 'can_vote_2' then 'can_vote_2'
    end
  end

private
  # общее количество раундов
  def total_rounds
    @total_rounds ||= Math.log(animes.count, 2).ceil * 2
  end

  # построение списка раундов контеста
  def build_rounds
    number = 1
    additional = false

    1.upto(total_rounds) do |i|
      self.rounds.create number: number, additional: additional

      number += 1 if additional || number == 1
      additional = !additional if i >= 2
    end
  end

  # заполнение раундов содержимым
  def fill_rounds
    rounds.each(&:take_votes)
  end

  def update_permalink
    self.permalink = self.title.permalinked if self.changes.include? :title
  end

  def update_thread_title
    thread.update_attribute(:title, self.title) if thread && thread.title != self.title
  end

  # создание AniMangaComment для элемента сразу после создания
  def create_comment_entry
    self.thread = ContestComment.new linked: self, section_id: Section::ContestsId
    self.thread.user_id = self.user_id
    self.thread.save!
  end
end
