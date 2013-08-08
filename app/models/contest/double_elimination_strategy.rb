class Contest::DoubleEliminationStrategy < Struct.new(:contest)
  # общее количество раундов
  def total_rounds
    @total_rounds ||= Math.log(contest.animes.count, 2).ceil * 2
  end

  # построение списка раундов контеста
  def build_rounds
    number = 1
    additional = false

    1.upto(total_rounds) do |i|
      contest.rounds.create number: number, additional: additional

      number += 1 if additional || number == 1
      additional = !additional if i >= 2
    end
  end

  # перенос в следующий раунд победителя
  def advance_winner(vote)
    return unless vote.round.next_round

    target_round = if vote.group == ContestRound::W && !vote.round.additional && vote.round.number > 1 && vote.strategy.with_additional_rounds?
      vote.round.next_round.next_round
    else
      vote.round.next_round
    end

    target_vote = if vote.round.number > 1 && !vote.round.additional
      target_round.votes
    else
      if vote.round.next_round.last?
        target_round.votes.select {|v| v.group == ContestRound::F }
      elsif vote.group == ContestRound::W || vote.group == ContestRound::S
        target_round.votes.select {|v| v.group == ContestRound::W }
      else
        target_round.votes.select {|v| v.group == ContestRound::L }
      end
    end.select { |v| v.left_id.nil? || v.right_id.nil? }.first

    if target_vote.left_id.nil?
      target_vote.left = vote.winner
    else
      target_vote.right = vote.winner
    end

    target_vote.save
  end

  # перенос в следующий раунд проигравшего
  def advance_loser(vote)
    return unless vote.round.next_round
    return if vote.group == ContestRound::L

    votes = vote.round.next_round.votes.select {|v| v.group == ContestRound::L }
    if vote.round.next_round.additional && (vote.round.next_round.number % 2) == 0
      take_order = (vote.round.next_round.number / 2) % 2 == 0 ? :first : :last

      target_vote = votes.select { |v| v.right_id.nil? && v.left_type.present? }.send take_order
      target_vote = votes.select { |v| v.left_id.nil? }.send take_order unless target_vote

      if target_vote.right_id.nil?
        target_vote.right = vote.loser
      else
        target_vote.left = vote.loser
      end
    else
      target_vote = votes.select { |v| v.left_id.nil? }.first
      target_vote = votes.select { |v| v.right_id.nil? }.first unless target_vote

      if target_vote.left_id.nil?
        target_vote.left = vote.loser
      else
        target_vote.right = vote.loser
      end
    end

    target_vote.save
  end

  # заполнение раунда голосованиями
  def populate(round, with_entrires, options)
    votes = round.votes

    entrires = if options[:shuffle]
      with_entrires.shuffle
    else
      with_entrires
    end

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

    entrires.each_slice(2).each_with_index do |(left,right), pair_index|
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
      pred_last = (entrires.size/2.0).ceil - 2
      if index >= contest.votes_per_round && (pair_index != pred_last || contest.votes_per_round < 3)
        date = date + contest.vote_interval.days
        index = 0
      end
    end
  end

  def with_additional_rounds?
    true
  end

  # итоги контеста
  def results
    contest.rounds.includes(votes: [left: [:studios, :genres], right: [:studios, :genres]]).reverse.map do |round|
      items = round.votes.map {|vote| pick_results vote }.compact.flatten

      if round.votes.first.group == ContestRound::F
        items
      else
        items.compact.sort_by { |v| -v.score }
      end
    end.flatten.take contest.animes.size
  end

  def pick_results(vote)
    if vote.group == ContestRound::F
      [ vote.winner, vote.loser ]
    elsif vote.group == ContestRound::W
      [ ]
    else
      [ vote.loser ]
    end
  end
end
