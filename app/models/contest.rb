class Contest < ActiveRecord::Base
  extend Enumerize
  include PermissionsPolicy

  MinimumAnimes = 5
  MaximumAnimes = 128

  belongs_to :user

  attr_accessible :title, :description, :started_on, :phases, :votes_per_round, :vote_duration, :vote_interval, :user_vote_key, :wave_days, :strategy_type

  validates_presence_of :title, :user, :started_on, :user_vote_key, :strategy_type
  validates_presence_of :vote_interval, :vote_duration, :votes_per_round, numericality: { greater_than: 0 }

  enumerize :strategy_type, in: [:double_elimination, :play_off], predicates: true
  delegate :total_rounds, :build_rounds, :results, to: :strategy

  has_many :links, class_name: ContestLink.name,
                   dependent: :destroy

  has_many :animes, through: :links,
                    source: :linked,
                    source_type: Anime.name,
                    order: :name

  has_many :rounds, class_name: ContestRound.name,
                    order: [:number, :additional],
                    dependent: :destroy

  has_one :thread, class_name: ContestComment.name,
                   foreign_key: :linked_id,
                   conditions: { linked_type: self.name },
                   dependent: :destroy

  before_save :update_permalink
  after_save :sync_thread

  state_machine :state, initial: :created do
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
    state :finished
    event :start do
      transition created: :started, if: lambda { |contest| contest.links.count >= MinimumAnimes && contest.links.count <= MaximumAnimes } # && Contest.all.none?(&:started?)
    end
    event :finish do
      transition started: :finished
    end

    before_transition created: :started do |contest, transition|
      contest.update_attribute :started_on, Date.today if contest.started_on < Date.today
      if contest.rounds.empty? || contest.rounds.any? { |v| v.votes.any? { |v| v.started_on < Date.today } }
        contest.prepare
      end
    end
    after_transition created: :started do |contest, transition|
      contest.send :create_thread unless contest.thread
      contest.rounds.first.start!
    end
    after_transition started: :finished do |contest, transition|
      contest.update_attribute :finished_on, Date.today
      User.update_all contest.user_vote_key => false
    end
  end

  class << self
    # текущий опрос
    def current
      Contest
          .where { state.eq('started') | (state.eq('finished') & finished_on.gte(DateTime.now - 1.week)) }
          .order(:started_on)
          .all
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
  end

  # побежденные аниме данным аниме
  def defeated_by(entry)
    @defeated ||= {}
    @defeated[entry.id] ||= ContestVote
        .where(round_id: rounds.map(&:id))
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

  # ключ в модели пользователя для хранении статуса проголосованности опроса
  def user_vote_key
    case self[:user_vote_key].to_s
      when 'can_vote_1' then 'can_vote_1'
      when 'can_vote_2' then 'can_vote_2'
    end
  end

  # стратегия создания раундов
  def strategy
    @strategy ||= if double_elimination?
      Contest::DoubleEliminationStrategy.new self
    else
      Contest::PlayOffStrategy.new self
    end
  end

  # заполнение раундов содержимым
  def fill_rounds
    rounds.each(&:take_votes)
  end

private
  def update_permalink
    self.permalink = title.permalinked if changes.include? :title
  end

  def sync_thread
    thread.update_attribute(:title, title) if thread && thread.title != title
  end

  # создание AniMangaComment для элемента сразу после создания
  def create_thread
    ContestComment.create! linked: self, section_id: Section::ContestsId, user: user
  end
end
