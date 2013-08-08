require 'spec_helper'

describe Contest::PlayOffStrategy do
  let(:strategy_type) { :play_off }

  describe :total_rounds do
    let(:contest) { build :contest, strategy_type: strategy_type }

    [[128,7], [65,7], [64,6], [50,6], [33,6], [32,5], [16,4], [9,4], [8,3], [7,3]].each do |animes, rounds|
      it "#{animes} -> #{rounds}" do
        contest.animes.stub(:count).and_return animes
        contest.total_rounds.should eq rounds
      end
    end
  end

  describe :build_rounds do
    let(:contest) { create :contest, strategy_type: strategy_type }

    [[128,7], [64,6], [32,5], [16,4], [8,3]].each do |animes, rounds|
      it "#{animes} -> #{rounds}" do
        contest.animes.stub(:count).and_return animes
        expect { contest.build_rounds }.to change(ContestRound, :count).by rounds
      end
    end

    it 'sets correct number&additional' do
      contest.animes.stub(:count).and_return 16
      contest.build_rounds

      contest.rounds[0].number.should eq 1
      contest.rounds.any? {|v| v.additional }.should be_false

      contest.rounds[1].number.should eq 2
      contest.rounds[2].number.should eq 3
      contest.rounds[3].number.should eq 4
    end
  end

  describe 'advance winner&loser' do
    let(:contest) { create :contest_with_5_animes, strategy_type: strategy_type }
    let(:w1) { contest.rounds[0].votes[0].left }
    let(:w2) { contest.rounds[0].votes[1].left }
    let(:w3) { contest.rounds[0].votes[2].left }

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

        contest.current_round.votes[2].should be_nil
      end
    end

    context 'II -> III' do
      before do
        2.times { |i| contest.rounds[i].votes.each { |v| v.update_attributes started_on: Date.yesterday, finished_on: Date.yesterday } }
        2.times do |i|
          contest.current_round.reload
          contest.current_round.finish!
        end
      end

      it 'winners&losers' do
        contest.current_round.votes[0].left.should eq w1
        contest.current_round.votes[0].right.should eq w3

        contest.current_round.votes[1].should be_nil
      end
    end
  end

  describe :with_additional_rounds? do
    subject { create(:contest, strategy_type: strategy_type).strategy }
    its(:with_additional_rounds?) { should be_false }
  end

  describe :results do
    let(:contest) { create :contest_with_8_animes, strategy_type: strategy_type }
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
      results[0].id.should eq contest.rounds[2].votes.first.winner.id
      results[1].id.should eq contest.rounds[2].votes.first.loser.id
    end

    it 'semifinal' do
      results[2].id.should eq contest.rounds[1].votes.first.loser.id
    end

    it 'regular rounds by score' do
      contest.rounds[0].votes[0].loser.update_attribute :score, 7
      contest.rounds[0].votes[1].loser.update_attribute :score, 8
      contest.rounds[0].votes[2].loser.update_attribute :score, 9
      contest.rounds[0].votes[3].loser.update_attribute :score, 6

      results[4].id.should eq contest.rounds[0].votes[2].loser.id
      results[5].id.should eq contest.rounds[0].votes[1].loser.id

      results[6].id.should eq contest.rounds[0].votes[0].loser.id
      results[7].id.should eq contest.rounds[0].votes[3].loser.id
    end
  end
end
