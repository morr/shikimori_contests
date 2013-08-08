class ContestRound < ActiveRecord::Base
  # стартовая группа
  S = 'S'
  # ни разу не проигравшая группа
  W = 'W'
  # один раз проигравшая группа
  L = 'L'
  # финальная группа
  F = 'F'

  belongs_to :contest
  has_many :votes, :class_name => ContestVote.name,
                   :foreign_key => :round_id,
                   :dependent => :destroy

  attr_accessible :number, :additional

  state_machine :state, :initial => :created do
    state :started
    state :finished

    event :start do
      transition :created => :started, :if => lambda { |round| round.votes.any? }
    end
    event :finish do
      transition :started => :finished, :if => lambda { |round| round.votes.all? { |v| v.finished? || v.can_finish? } }
    end

    after_transition :created => :started do |round, transition|
      round.votes.select {|v| v.started_on <= Date.today }.each(&:start!)
    end

    before_transition :started => :finished do |round, transition|
      round.votes.select(&:started?).each(&:finish!)
    end

    after_transition :started => :finished do |round, transition|
      if round.next_round
        round.next_round.start!
      else
        round.contest.finish!
      end
    end
  end

  # название раунда
  def title(short=false)
    "#{short ? '' : 'Раунд '}#{number}#{'a' if additional}"
  end

  def to_param
    "#{number}#{'a' if additional}"
  end

  # заполнение раунда голосованиями из предыдущих раундов
  def take_votes
    if first?
      strategy.populate self, contest.animes, group: ContestRound::S, shuffle: true
    elsif last?
      strategy.populate self, 0.upto(1).map { ContestVote::Undefined }, group: ContestRound::F, date: prior_round.votes.last.finished_on + contest.vote_interval.days
    else
      losers_count = [
        (number > 2 ?
          prior_round.votes.count :
          (prior_round.votes.map { |v| v.right_type ? 2 : 1 }.sum / 2.0).floor
        ),
        1
      ].max

      winners_round = if prior_round.votes.any? { |v| v.group == W || v.group == S }
        prior_round
      else
        prior_round.prior_round
      end
      winners_count = (winners_round.votes.select { |v| v.group == W || v.group == S }
          .map { |v| v.right_type ? 2 : 1 }.sum / 2.0).ceil

      if additional
        strategy.populate self, 1.upto(losers_count).map { ContestVote::Undefined }, group: ContestRound::L, date: prior_round.votes.last.finished_on+contest.vote_interval.days
      else
        strategy.populate self, 1.upto(winners_count).map { ContestVote::Undefined }, group: ContestRound::W, date: prior_round.votes.last.finished_on+contest.vote_interval.days

        if strategy.with_additional_rounds?
          strategy.populate self, 1.upto(losers_count).map { ContestVote::Undefined }, group: ContestRound::L
        end
      end
    end
  end

  # предыдущий раунд
  def prior_round
    @prior_round ||= begin
      index = contest.rounds.index self
      if index == 0
        nil
      else
        contest.rounds[index-1]
      end
    end
  end

  # следующий раунд
  def next_round
    @next_round ||= begin
      index = contest.rounds.index self
      if index == contest.rounds.size - 1
        nil
      else
        contest.rounds[index+1]
      end
    end
  end

  # первое ли это голосование
  def first?
    self == contest.rounds.first
  end

  # последние ли это голосование
  def last?
    self == contest.rounds.last
  end

  # стратегия турнира
  def strategy
    contest.strategy
  end
end
