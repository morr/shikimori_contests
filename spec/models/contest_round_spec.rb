require 'spec_helper'

describe ContestRound do
  context '#relations' do
    it { should belong_to :contest }
    it { should have_many :votes }
  end

  describe 'states' do
    let(:round) { create :contest_round, contest: create(:contest_with_5_animes, state: 'started') }

    it 'full cycle' do
      round.created?.should be_true

      round.take_votes
      round.start!
      round.started?.should be_true

      round.votes.each {|v| v.state = 'finished' }
      round.finish!
      round.finished?.should be_true
    end

    describe :can_start? do
      subject { round.can_start? }

      context 'no votes' do
        it { should be_false }
      end

      context 'has votes' do
        before { round.take_votes }
        it { should be_true }
      end
    end

    describe :can_finish? do
      subject { round.can_finish? }

      context 'not finished votes' do
        before do
          round.take_votes
          round.start!
        end
        it { should be_false }
      end

      context 'finished votes' do
        before do
          round.take_votes
          round.start!
        end

        context 'all finished' do
          before { round.votes.each {|v| v.state = 'finished' } }
          it { should be_true }
        end

        context 'all can_finish' do
          before { round.votes.each {|v| v.stub(:can_finish?).and_return true } }
          it { should be_true }
        end
      end
    end

    context 'after started' do
      it 'starts today votes' do
        round.take_votes
        round.start!
        round.votes.each do |vote|
          vote.started?.should be_true
        end
      end

      it 'does not start votes in future' do
        round.take_votes
        round.votes.each {|v| v.started_on = Date.tomorrow }
        round.start!

        round.votes.each do |vote|
          vote.started?.should be_false
        end
      end
    end

    context 'before finished' do
      before do
        round.take_votes
        round.start!
        round.votes.each {|v| v.finished_on = Date.yesterday }
      end

      describe 'finishes unfinished votes' do
        before { round.finish! }
        it { round.votes.each {|v| v.finished?.should be_true } }
      end
    end

    context 'after finished' do
      before do
        round.take_votes
        round.start!
        round.votes.each {|v| v.finished_on = Date.yesterday }
      end
      let(:next_round) { create :contest_round }

      it 'starts next round' do
        round.stub(:next_round).and_return(next_round)
        next_round.should_receive(:start!)
        round.finish!
      end

      it 'finishes contest' do
        round.finish!
        round.contest.finished?.should be_true
      end
    end
  end

  describe :prior_round do
    let(:contest) { create :contest_with_5_animes }
    before { contest.send :build_rounds }

    it 'I' do
      contest.rounds[0].prior_round.should be_nil
    end

    it 'II' do
      contest.rounds[1].prior_round.should eq contest.rounds[0]
    end

    it 'IIa' do
      contest.rounds[2].prior_round.should eq contest.rounds[1]
    end

    it 'III' do
      contest.rounds[3].prior_round.should eq contest.rounds[2]
    end

    it 'IIIa' do
      contest.rounds[4].prior_round.should eq contest.rounds[3]
    end

    it 'IV' do
      contest.rounds[5].prior_round.should eq contest.rounds[4]
    end
  end

  describe :next_round do
    let(:contest) { create :contest_with_5_animes }
    before { contest.send :build_rounds }

    it 'I' do
      contest.rounds[0].next_round.should eq contest.rounds[1]
    end

    it 'II' do
      contest.rounds[1].next_round.should eq contest.rounds[2]
    end

    it 'IIa' do
      contest.rounds[2].next_round.should eq contest.rounds[3]
    end

    it 'III' do
      contest.rounds[3].next_round.should eq contest.rounds[4]
    end

    it 'IIIa' do
      contest.rounds[4].next_round.should eq contest.rounds[5]
    end

    it 'IV' do
      contest.rounds[5].next_round.should eq nil
    end
  end

  describe :take_votes do
    context '19 animes' do
      let(:contest) { create :contest_with_19_animes, votes_per_round: 3 }
      before { contest.send :build_rounds }

      context 'I' do
        let(:round) { contest.rounds.first }
        before { contest.rounds[0..0].each(&:take_votes) }

        it 'should not left last vote for next day' do
          round.votes.map(&:started_on).map(&:to_s).uniq.should have(3).items
        end
      end

      context 'II' do
        let(:round) { contest.rounds[1] }
        before { contest.rounds[0..1].each(&:take_votes) }

        it 'should make the same date grouping as in the first round' do
          round.votes.map(&:started_on).map(&:to_s).uniq.should have(3).items
        end
      end
    end

    context '5 animes' do
      let(:contest) { create :contest_with_5_animes }
      before { contest.send :build_rounds }

      context 'I' do
        let(:round) { contest.rounds.first }
        before { contest.rounds[0..0].each(&:take_votes) }

        it 'valid' do
          round.votes.should have(3).items
          round.votes.each {|vote| vote.group.should eq ContestRound::S }
          round.votes.first.started_on.should eq contest.started_on
          round.votes.first.right_type.should_not be_nil
          round.votes.last.right_type.should be_nil
        end
      end

      context 'II' do
        let(:round) { contest.rounds[1] }
        before { contest.rounds[0..1].each(&:take_votes) }

        it 'valid' do
          round.votes.should have(3).items
          round.votes[0..1].each {|vote| vote.group.should eq ContestRound::W }
          round.votes[2..2].each {|vote| vote.group.should eq ContestRound::L }
          round.votes.first.started_on.should eq (round.prior_round.votes.last.finished_on+contest.vote_interval.days)
          round.votes.first.right_type.should_not be_nil
        end
      end

      context 'IIa' do
        let(:round) { contest.rounds[2] }
        before { contest.rounds[0..2].each(&:take_votes) }

        it 'valid' do
          round.votes.should have(1).item
          round.votes.each {|vote| vote.group.should eq ContestRound::L }
          round.votes.first.started_on.should eq (round.prior_round.votes.last.finished_on+contest.vote_interval.days)
          round.votes.first.right_type.should_not be_nil
        end
      end

      context 'III' do
        let(:round) { contest.rounds[3] }
        before { contest.rounds[0..3].each(&:take_votes) }

        it 'valid' do
          round.votes.should have(2).items
          round.votes.first.group.should eq ContestRound::W
          round.votes.last.group.should eq ContestRound::L
          round.votes.first.started_on.should eq (round.prior_round.votes.last.finished_on+contest.vote_interval.days)
          round.votes.first.right_type.should_not be_nil
        end
      end

      context 'IIIa' do
        let(:round) { contest.rounds[4] }
        before { contest.rounds[0..4].each(&:take_votes) }

        it 'valid' do
          round.votes.should have(1).item
          round.votes.first.group.should eq ContestRound::L
          round.votes.first.right_type.should_not be_nil
        end
      end

      context 'IV' do
        let(:round) { contest.rounds.last }
        before { contest.rounds.each(&:take_votes) }

        it 'valid' do
          round.votes.should have(1).item
          round.votes.first.group.should eq ContestRound::F
          round.votes.first.started_on.should eq (round.prior_round.votes.last.finished_on+contest.vote_interval.days)
          round.votes.first.right_type.should_not be_nil
        end
      end
    end
  end

  describe 'first&last' do
    let(:contest) { create :contest_with_5_animes }
    before { contest.send :build_rounds }

    it 'correct' do
      contest.rounds.first.first?.should be_true
      contest.rounds.first.last?.should be_false

      1.upto(contest.rounds.count - 2) do |index|
        contest.rounds[index].first?.should be_false
        contest.rounds[index].last?.should be_false
      end

      contest.rounds.last.first?.should be_false
      contest.rounds.last.last?.should be_true
    end
  end
end
