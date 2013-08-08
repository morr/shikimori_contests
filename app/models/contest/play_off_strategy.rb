class Contest::PlayOffStrategy < Contest::DoubleEliminationStrategy
  # общее количество раундов
  def total_rounds
    @total_rounds ||= Math.log(contest.animes.count, 2).ceil
  end

  # построение списка раундов контеста
  def build_rounds
    1.upto(total_rounds) do |number|
      contest.rounds.create number: number, additional: false
    end
  end

  def advance_loser(vote)
  end

  def with_additional_rounds?
    false
  end

  def pick_results(vote)
    if vote.group == ContestRound::F
      [ vote.winner, vote.loser ]
    elsif vote.group == ContestRound::W || vote.group == ContestRound::S
      [ vote.loser ]
    else
      [ ]
    end
  end
end
