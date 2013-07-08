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
      fill_votes contest.animes, group: ContestRound::S, shuffle: true
    elsif last?
      fill_votes 0.upto(1).map { ContestVote::Undefined }, group: ContestRound::F, date: prior_round.votes.last.finished_on+contest.vote_interval.days
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
        fill_votes 1.upto(losers_count).map { ContestVote::Undefined }, group: ContestRound::L, date: prior_round.votes.last.finished_on+contest.vote_interval.days
      else
        fill_votes 1.upto(winners_count).map { ContestVote::Undefined }, group: ContestRound::W, date: prior_round.votes.last.finished_on+contest.vote_interval.days
        fill_votes 1.upto(losers_count).map { ContestVote::Undefined }, group: ContestRound::L
      end
    end
  end

  # перенос в следующий раунд победителя
  def advance_winner(item, group)
    return unless next_round

    target_round = if group == W && !additional && number > 1
      next_round.next_round
    else
      next_round
    end

    vote = if number > 1 && !additional
      target_round.votes
    else
      if next_round.last?
        target_round.votes.select {|v| v.group == F }
      elsif group == W || group == S
        target_round.votes.select {|v| v.group == W }
      else
        target_round.votes.select {|v| v.group == L }
      end
    end.select { |v| v.left_id.nil? || v.right_id.nil? }.first

    if vote.left_id.nil?
      vote.left = item
    else
      vote.right = item
    end

    vote.save
  end

  # перенос в следующий раунд проигравшего
  def advance_loser(item, group)
    return unless next_round
    return if group == L

    votes = next_round.votes.select {|v| v.group == L }
    if next_round.additional && (next_round.number % 2) == 0
      take_order = (next_round.number / 2) % 2 == 0 ? :first : :last

      vote = votes.select { |v| v.right_id.nil? && v.left_type.present? }.send take_order
      vote = votes.select { |v| v.left_id.nil? }.send take_order unless vote

      if vote.right_id.nil?
        vote.right = item
      else
        vote.left = item
      end
    else
      vote = votes.select { |v| v.left_id.nil? }.first
      vote = votes.select { |v| v.right_id.nil? }.first unless vote

      if vote.left_id.nil?
        vote.left = item
      else
        vote.right = item
      end
    end

    vote.save
  end

  # предыдущий раунд
  def prior_round
    @prior_round ||= contest.rounds.select do |round|
      if additional
        round.number == self.number
      else
        round.number == self.number - 1 && (round.additional || round.number == 1)
      end
    end.first
  end

  # следующий раунд
  def next_round
    @next_round ||= contest.rounds.select do |round|
      if self.number == 1
        round.number == 2 && !additional
      elsif additional
        round.number == self.number + 1 && !round.additional
      else
        round.number == self.number && round.additional
      end
    end.first
  end

  # первое ли это голосование
  def first?
    self == contest.rounds.first
  end

  # последние ли это голосование
  def last?
    self == contest.rounds.last
  end

private
  # заполнение раунда голосованиями
  def fill_votes(animes, options)
    animes = animes.shuffle if options[:shuffle]

    index = votes.count % contest.votes_per_round
    date = options[:date] || if votes.any?
      if index == 0
        votes.last.started_on + contest.vote_interval.days
      else
        votes.last.started_on
      end
    else
      contest.started_on
    end

    #animes.each_slice(2) do |left, right|
    animes.each_slice(2).each_with_index do |pair, pair_index|
      left, right = pair
      votes.create({
        left_type: Anime.name,
        left_id: left && left != ContestVote::Undefined ? left.id : nil,
        right_type: right ? Anime.name : nil,
        right_id: right && right != ContestVote::Undefined ? right.id : nil,
        group: options[:group],
        started_on: date,
        finished_on: date + [0, contest.vote_duration - 1].max.days
      })

      index += 1
      pred_last = (animes.size/2.0).ceil - 2
      if index >= contest.votes_per_round && (pair_index != pred_last || contest.votes_per_round < 3)
        date = date + contest.vote_interval.days
        index = 0
      end
    end
  end
end
