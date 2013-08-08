require 'spec_helper'

describe ContestVote do
  context '#relations' do
    it { should belong_to :round }
    it { should belong_to :left }
    it { should belong_to :right }
    it { should have_many :user_votes }
  end

  let(:user) { create :user }

  describe 'states' do
    let(:vote) { create :contest_vote, started_on: Date.yesterday, finished_on: Date.yesterday }

    it 'full cycle' do
      vote.created?.should be_true
      vote.start!
      vote.started?.should be_true
      vote.finish!
      vote.finished?.should be_true
    end

    describe :can_vote? do
      subject { vote.can_vote? }

      context 'created' do
        it { should be_false }
      end

      context 'started' do
        before { vote.start! }
        it { should be_true }
      end
    end

    describe :can_finish? do
      subject { vote.can_finish? }
      before { vote.start! }

      context 'true' do
        before { vote.finished_on = Date.yesterday }
        it { should be_true }
      end

      context 'false' do
        before { vote.finished_on = Date.today }
        it { should be_false }
      end
    end

    context :can_start? do
      subject { vote.can_start? }

      context 'true' do
        before { vote.started_on = Date.today }
        it { should be_true }
      end

      context 'false' do
        before { vote.started_on = Date.tomorrow }
        it { should be_false }
      end
    end

    context 'after started' do
      [:can_vote_1, :can_vote_2].each do |user_vote_key|
        describe user_vote_key do
          before do
            vote.round.contest.update_attribute :user_vote_key, user_vote_key
            vote.reload

            create :user
            create :user

            vote.round.contest.stub(:started?).and_return true
            vote.start!
          end

          it { User.all.all? {|v| v.can_vote?(vote.round.contest) }.should be true }
        end
      end

      describe 'right_id = nil, right_type = Anime' do
        let(:vote) { create :contest_vote, started_on: Date.yesterday, finished_on: Date.yesterday, right_id: nil, right_type: Anime.name }
        before { vote.start! }
        it { vote.right_type.should be_nil }
      end

      describe 'left_id = nil, right_id != nil' do
        let(:vote) { create :contest_vote, started_on: Date.yesterday, finished_on: Date.yesterday, left_id: nil, left_type: Anime.name }
        before { vote.start! }
        it { vote.left_type.should_not be_nil }
        it { vote.left_id.should_not be_nil }
        it { vote.right_type.should be_nil }
        it { vote.right_id.should be_nil }
      end
    end

    context 'after finished' do
      before { vote.start! }

      it 'should be false' do
        vote.finish!
        vote.can_vote?.should be_false
      end

      context 'no right variant' do
        before do
          vote.right = nil
          vote.finish!
        end

        it { vote.winner_id.should eq vote.left_id }
      end

      context 'left_votes > right_votes' do
        before do
          vote.contest_user_votes.create user_id: 1, ip: '1', item_id: vote.left_id
          vote.finish!
        end

        it { vote.winner_id.should eq vote.left_id }
      end

      context 'right_votes > left_votes' do
        before do
          vote.contest_user_votes.create user_id: 1, ip: '1', item_id: vote.right_id
          vote.finish!
        end

        it { vote.winner_id.should eq vote.right_id }
      end

      context 'left_votes == right_votes' do
        context 'left.score > right.score' do
          before do
            vote.left.update_attribute :score, 2
            vote.right.update_attribute :score, 1
            vote.finish!
          end

          it { vote.winner_id.should eq vote.left_id }
        end

        context 'right.score > left.score' do
          before do
            vote.left.update_attribute :score, 1
            vote.right.update_attribute :score, 2
            vote.finish!
          end

          it { vote.winner_id.should eq vote.right_id }
        end

        context 'left.score == right.score' do
          before do
            vote.left.update_attribute :score, 2
            vote.right.update_attribute :score, 2
            vote.finish!
          end

          it { vote.winner_id.should eq vote.left_id }
        end
      end

      describe 'advance participants' do
        it 'winner' do
          vote.strategy.should_receive(:advance_winner).with vote
          vote.finish!
        end

        it 'loser' do
          vote.strategy.should_receive(:advance_loser).with vote
          vote.finish!
        end
      end
    end
  end

  describe :vote_for do
    let(:vote) { create :contest_vote, state: 'started' }

    it 'creates ContestUserVote' do
      expect {
        vote.vote_for 'left', user, "123"
      }.to change(ContestUserVote, :count).by 1
    end

    context 'no vote' do
      context 'left' do
        before { vote.vote_for 'left', user, "123" }
        it { vote.user_votes.first.item_id.should eq vote.left_id }
      end

      context 'right' do
        before { vote.vote_for 'right', user, "123" }
        it { vote.user_votes.first.item_id.should eq vote.right_id }
      end

      context 'none' do
        before { vote.vote_for 'none', user, "123" }
        it { vote.user_votes.first.item_id.should eq 0 }
      end

      context 'user' do
        before { vote.vote_for 'right', user, "123" }
        it { vote.user_votes.first.user_id.should eq user.id }
      end

      context 'ip' do
        before { vote.vote_for 'right', user, "123" }
        it { vote.user_votes.first.ip.should eq '123' }
      end
    end

    context 'has vote' do
      before do
        vote.vote_for 'left', user, "123"
        vote.vote_for 'right', user, "123"
      end

      it { vote.user_votes.first.item_id.should eq vote.right_id }
      it { vote.user_votes.count.should eq 1 }
    end
  end

  describe :voted_for? do
    let(:vote) { create :contest_vote, state: 'started' }

    context 'not voted' do
      it { vote.voted_for?(user, '').should be_nil }
    end

    context 'no user' do
      it { vote.voted_for?(nil, '').should be_nil }
    end

    context 'voted' do
      context 'left' do
        before { vote.vote_for(:left, user, '') }
        it { vote.voted_for?(user, '').should be :left }
      end

      context 'right' do
        before { vote.vote_for(:right, user, '') }
        it { vote.voted_for?(user, '').should be :right }
      end

      context 'none' do
        before { vote.vote_for(:none, user, '') }
        it { vote.voted_for?(user, '').should be :none }
      end
    end
  end

  describe :voted? do
    let!(:vote) { create :contest_vote, state: 'started' }
    let(:vote_with_user_vote) { ContestVote.with_user_vote(user, '').first }
    subject { vote_with_user_vote.voted? }

    context 'not voted' do
      it { should be_false }
    end

    context 'voted' do
      context 'when really voted' do
        before { vote.vote_for(:left, user, '') }
        it { should be_true }
      end

      context 'when right_type is nil' do
        before { vote_with_user_vote.right_type = nil }
        it { should be_true }
      end
    end
  end

  describe :state_with_voted do
    subject { ContestVote.with_user_vote(user, '').first.state_with_voted }

    context 'finished' do
      let!(:vote) { create :contest_vote, state: 'finished' }
      it { should eq 'finished' }
    end

    context 'created' do
      let!(:vote) { create :contest_vote }
      it { should eq 'created' }
    end

    context 'started' do
      let!(:vote) { create :contest_vote, state: 'started' }

      context 'not voted' do
        it { should eq 'pending' }
      end

      context 'voted' do
        before { vote.vote_for :left, user, '' }
        it { should eq 'voted' }
      end
    end
  end

  describe :update_user do
    let(:round) { create :contest_round, state: 'started' }
    subject { user.can_vote_1? }
    before do
      create :contest_vote, state: 'started', left_type: 'Anime', right_type: 'Anime', left_id: 1, right_id: 2, round_id: round.id
      create :contest_vote, state: 'started', left_type: 'Anime', right_type: 'Anime', left_id: 3, right_id: 4, round_id: round.id
    end

    describe 'not updated' do
      let(:user) { create :user, can_vote_1: true }
      before do
        round.votes.last.vote_for 'left', user, 'z'
        ContestVote.first.update_user user, 'z'
      end

      it { should be_true }
    end

    describe 'updated' do
      let(:user) { create :user, can_vote_1: true }
      before do
        round.votes.first.vote_for 'left', user, 'z'
        round.votes.last.vote_for 'left', user, 'z'
        round.votes.first.update_user user, 'z'
      end

      it { should be_false }
    end
  end

  describe 'left_votes & right_votes & refrained_votes' do
    let(:vote) { create :contest_vote }
    before do
      vote.contest_user_votes.create user_id: 1, ip: '1', item_id: vote.left_id
      vote.contest_user_votes.create user_id: 2, ip: '2', item_id: vote.left_id
      vote.contest_user_votes.create user_id: 3, ip: '3', item_id: vote.left_id
      vote.contest_user_votes.create user_id: 4, ip: '4', item_id: vote.right_id
      vote.contest_user_votes.create user_id: 5, ip: '5', item_id: 0
      vote.contest_user_votes.create user_id: 6, ip: '6', item_id: 0
    end

    it { vote.left_votes.should eq 3 }
    it { vote.right_votes.should eq 1 }
    it { vote.refrained_votes.should eq 2 }
  end

  describe :winner do
    let(:vote) { create :contest_vote, state: 'finished' }
    subject { vote.winner }

    describe 'left' do
      before { vote.winner_id = vote.left_id }
      its(:id) { should eq vote.left.id }
    end

    describe 'right' do
      before { vote.winner_id = vote.right_id }
      its(:id) { should eq vote.right.id }
    end
  end

  describe :loser do
    let(:vote) { create :contest_vote, state: 'finished' }
    subject { vote.loser }

    describe 'left' do
      before { vote.winner_id = vote.left_id }
      its(:id) { should eq vote.right.id }
    end

    describe 'right' do
      before { vote.winner_id = vote.right_id }
      its(:id) { should eq vote.left.id }
    end

    describe 'no loser' do
      before do
        vote.winner_id = vote.left_id
        vote.right = nil
      end
      it { vote.loser.should be_nil }
    end
  end
end
