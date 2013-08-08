require 'spec_helper'

describe Contest::DoubleEliminationStrategy do
  let(:strategy_type) { :double_elimination }

  describe :total_rounds do
    let(:contest) { build :contest, strategy_type: strategy_type }

    [[128,14], [65,14], [64,12], [50,12], [33,12], [32,10], [16,8], [9,8], [8,6], [7,6]].each do |animes, rounds|
      it "#{animes} -> #{rounds}" do
        contest.animes.stub(:count).and_return animes
        contest.total_rounds.should eq rounds
      end
    end
  end

  describe :build_rounds do
    let(:contest) { create :contest, strategy_type: strategy_type }

    [[128,14], [64,12], [32,10], [16,8], [8,6]].each do |animes, rounds|
      it "#{animes} -> #{rounds}" do
        contest.animes.stub(:count).and_return animes
        expect { contest.build_rounds }.to change(ContestRound, :count).by rounds
      end
    end

    it 'sets correct number&additional' do
      contest.animes.stub(:count).and_return 16
      contest.build_rounds

      contest.rounds[0].number.should eq 1
      contest.rounds[0].additional.should be_false

      contest.rounds[1].number.should eq 2
      contest.rounds[1].additional.should be_false
      contest.rounds[2].number.should eq 2
      contest.rounds[2].additional.should be_true

      contest.rounds[3].number.should eq 3
      contest.rounds[3].additional.should be_false
      contest.rounds[4].number.should eq 3
      contest.rounds[4].additional.should be_true

      contest.rounds[5].number.should eq 4
      contest.rounds[5].additional.should be_false
      contest.rounds[6].number.should eq 4
      contest.rounds[6].additional.should be_true

      contest.rounds[7].number.should eq 5
      contest.rounds[7].additional.should be_false
    end
  end

  describe 'advance winner&loser' do
    let(:contest) { create :contest_with_5_animes, strategy_type: strategy_type }
    let(:w1) { contest.rounds[0].votes[0].left }
    let(:w2) { contest.rounds[0].votes[1].left }
    let(:w3) { contest.rounds[0].votes[2].left }
    let(:l1) { contest.rounds[0].votes[0].right }
    let(:l2) { contest.rounds[0].votes[1].right }

    before { contest.start! }

    context 'I -> II' do
      before do
        1.times { |i| contest.rounds[i].votes.each { |v| v.update_attributes started_on: Date.yesterday, finished_on: Date.yesterday } }
        1.times do
          contest.current_round.reload
          contest.current_round.finish!
        end
      end

      it 'winners&losers' do
        contest.current_round.votes[0].left.should eq w1
        contest.current_round.votes[0].right.should eq w2

        contest.current_round.votes[1].left.should eq w3
        contest.current_round.votes[1].right.should be_nil

        contest.current_round.votes[2].left.should eq l1
        contest.current_round.votes[2].right.should eq l2
      end
    end

    context 'II -> IIa, II -> III' do
      before do
        2.times { |i| contest.rounds[i].votes.each { |v| v.update_attributes started_on: Date.yesterday, finished_on: Date.yesterday } }
        2.times do |i|
          contest.current_round.reload
          contest.current_round.finish!
        end
      end

      it 'winners&losers' do
        contest.current_round.votes[0].left.should eq l1
        contest.current_round.votes[0].right.should eq w2

        contest.current_round.next_round.votes[0].left.should eq w1
        contest.current_round.next_round.votes[0].right.should eq w3
      end
    end

    context 'IIa -> III' do
      before do
        3.times { |i| contest.rounds[i].votes.each { |v| v.update_attributes started_on: Date.yesterday, finished_on: Date.yesterday } }
        3.times do |i|
          contest.current_round.reload
          contest.current_round.finish!
        end
      end

      it 'winners' do
        contest.current_round.votes[1].left.should eq l1
        contest.current_round.votes[1].right.should be_nil
      end
    end

    context 'III -> IIIa, III -> IV' do
      before do
        4.times { |i| contest.rounds[i].votes.each { |v| v.update_attributes started_on: Date.yesterday, finished_on: Date.yesterday } }
        4.times do |i|
          contest.current_round.reload
          contest.current_round.finish!
        end
      end

      it 'winners&losers' do
        contest.current_round.votes[0].left.should eq w3
        contest.current_round.votes[0].right.should eq l1

        contest.current_round.next_round.votes[0].left.should eq w1
        contest.current_round.next_round.votes[0].right.should be_nil
      end
    end

    context 'III -> IV' do
      before do
        5.times { |i| contest.rounds[i].votes.each { |v| v.update_attributes started_on: Date.yesterday, finished_on: Date.yesterday } }
        5.times do |i|
          contest.current_round.reload
          contest.current_round.finish!
        end
      end

      it 'winners' do
        contest.current_round.votes[0].right.should eq w3
      end
    end
  end

  describe :populate do
    let(:strategy) { round.contest.strategy }
    let(:round) { create :contest_round, contest: create(:contest, votes_per_round: 4, vote_duration: 4) }
    let(:animes) { 1.upto(11).map { create :anime } }

    it 'creates animes/2 votes' do
      expect { strategy.populate round, animes, group: ContestRound::W }.to change(ContestVote, :count).by (animes.size.to_f / 2).ceil
    end

    it 'populates left&right correctly' do
      strategy.populate round, animes, shuffle: false

      round.votes[0].left_id.should eq animes[0].id
      round.votes[0].right_id.should eq animes[1].id

      round.votes[1].left_id.should eq animes[2].id
      round.votes[1].right_id.should eq animes[3].id

      round.votes[5].left_id.should eq animes[10].id
      round.votes[5].right_id.should be_nil
    end

    describe 'dates' do
      before { strategy.populate round, animes, shuffle: false }
      let(:votes_per_round) { round.contest.votes_per_round }

      it 'first of first round' do
        round.votes[0].started_on.should eq round.contest.started_on
        round.votes[0].finished_on.should eq round.contest.started_on + (round.contest.vote_duration-1).days
      end

      it 'last of first round' do
        round.votes[votes_per_round - 1].started_on.should eq round.contest.started_on
        round.votes[votes_per_round - 1].finished_on.should eq round.contest.started_on + (round.contest.vote_duration-1).days
      end

      it 'first of second round' do
        round.votes[votes_per_round].started_on.should eq round.contest.started_on + round.contest.vote_interval.days
        round.votes[votes_per_round].finished_on.should eq round.contest.started_on + (round.contest.vote_interval-1).days + round.contest.vote_duration.days
      end

      context 'additional populate' do
        before do
          @prior_last_vote = round.votes.last
          @prior_count = round.votes.count
          strategy.populate round, animes, shuffle: false
        end

        it 'continues from last vote' do
          round.votes[@prior_count].started_on.should eq @prior_last_vote.started_on
        end
      end
    end

    describe :shuffle do
      let(:ordered?) { round.votes[0].left_id == animes[0].id && round.votes[0].right_id == animes[1].id && round.votes[1].left_id == animes[2].id && round.votes[1].right_id == animes[3].id }

      context 'false' do
        before { strategy.populate round, animes, shuffle: false }

        it 'populates votes with ordered animes' do
          ordered?.should be_true
        end
      end

      context 'true' do
        before { strategy.populate round, animes, shuffle: true }

        it 'populates votes with shuffled animes' do
          ordered?.should be_false
        end
      end
    end
  end

  describe :with_additional_rounds? do
    subject { create(:contest, strategy_type: strategy_type).strategy }
    its(:with_additional_rounds?) { should be_true }
  end

  describe :results do
    let(:contest) { create :contest_with_8_animes }
    let(:results) { contest.results }
    before do
      contest.start!
      contest.rounds.each do |round|
        contest.current_round.votes.each { |v| v.update_attributes started_on: Date.yesterday, finished_on: Date.yesterday }
        contest.process!
        contest.reload
      end
    end

    it 'correct count' do
      results.should have(contest.animes.size).items
    end

    it 'final' do
      results[0].id.should eq contest.rounds[5].votes.first.winner.id
      results[1].id.should eq contest.rounds[5].votes.first.loser.id
    end

    it 'semifinal' do
      results[2].id.should eq contest.rounds[4].votes.first.loser.id
      results[3].id.should eq contest.rounds[3].votes.last.loser.id
    end

    it 'regular rounds by score' do
      contest.rounds[1].votes[3].loser.update_attribute :score, 9
      contest.rounds[1].votes[2].loser.update_attribute :score, 5

      results[4].id.should eq contest.rounds[2].votes.first.loser.id
      results[5].id.should eq contest.rounds[2].votes.last.loser.id

      results[6].id.should eq contest.rounds[1].votes[3].loser.id
      results[7].id.should eq contest.rounds[1].votes[2].loser.id
    end
  end
end
