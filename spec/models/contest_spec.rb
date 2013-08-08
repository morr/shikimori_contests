require 'spec_helper'

describe Contest do
  context '#relations' do
    it { should belong_to :user }

    it { should have_many :links }
    it { should have_many :animes }
    it { should have_many :rounds }

    it { should have_one :thread }
  end

  describe '#validations' do
    it { should validate_presence_of :title }
    it { should validate_presence_of :user }
    it { should validate_presence_of :strategy_type }
    it { should validate_presence_of :started_on }
    it { should validate_presence_of :user_vote_key }
  end

  describe 'states' do
    let(:contest) { create :contest_with_5_animes }

    it 'full cycle' do
      contest.created?.should be_true
      contest.start!
      contest.started?.should be_true
      contest.finish!
      contest.finished?.should be_true
    end

    describe :can_start? do
      subject { contest.can_start? }
      context 'normal count' do
        before { contest.links.stub(:count).and_return Contest::MinimumAnimes + 1 }
        it { should be_true }
      end

      context 'Contest::MinimumAnimes' do
        before { contest.links.stub(:count).and_return Contest::MinimumAnimes - 1 }
        it { should be_false }
      end

      context 'Contest::MaximumAnimes' do
        before { contest.links.stub(:count).and_return Contest::MaximumAnimes + 1 }
        it { should be_false }
      end
    end

    context 'before started' do
      it 'builds rounds' do
        contest.start!
        contest.rounds.should_not be_empty
      end

      it 'fills first contest votes' do
        contest.start!
        contest.rounds.first.votes.should_not be_empty
      end

      context 'when started_on expired' do
        before { contest.update_attribute :started_on, Date.yesterday }

        it 'updates started_on' do
          contest.start!
          contest.started_on.should eq Date.today
        end

        it 'rebuilds votes' do
          contest.prepare
          contest.should_receive :prepare
          contest.start!
        end
      end
    end

    context 'after started' do
      it 'starts first round' do
        contest.start!
        contest.rounds.first.started?.should be_true
      end

      it 'creates thread' do
        contest.start!
        contest.reload.thread.present?.should be_true
      end
    end

    context 'after finished' do
      [:can_vote_1, :can_vote_2].each do |user_vote_key|
        describe user_vote_key do
          before do
            create :user, user_vote_key => true
            create :user, user_vote_key => true

            contest.update_attribute :user_vote_key, user_vote_key
            contest.start!
            contest.stub(:can_finish?).and_return true
            contest.finish!
            contest.reload
          end

          it { User.all.none? {|v| v.can_vote?(contest) }.should be true }
          it { contest.finished_on.should eq Date.today }
        end
      end
    end
  end

  describe :prepare do
    let(:contest) { create :contest_with_5_animes }

    it 'deletes existing rounds' do
      round = create :contest_round, contest_id: contest.id
      contest.rounds << round
      contest.prepare

      expect {
        round.reload
      }.to raise_error ActiveRecord::RecordNotFound
    end

    it 'build_rounds&fill_rounds' do
      contest.should_receive :build_rounds
      contest.should_receive :fill_rounds
      contest.prepare
    end
  end

  describe :fill_rounds do
    let(:contest) { create :contest_with_5_animes }
    before { contest.build_rounds }

    it 'calls take_votes for each round' do
      contest.rounds.each {|v| v.should_receive :take_votes }
      contest.fill_rounds
    end
  end

  describe :process! do
    let(:contest) { create :contest_with_5_animes }
    let(:round) { contest.current_round }
    before { contest.start }

    it 'starts votes' do
      round.votes.last.state = 'created'
      contest.process!
      round.votes.last.started?.should be_true
    end

    it 'finishes votes' do
      round.votes.last.finished_on = Date.yesterday
      contest.process!
      round.votes.last.finished?.should be_true
    end

    it 'finishes round' do
      round.votes.each { |v| v.finished_on = Date.yesterday }
      contest.process!
      round.finished?.should be_true
    end

    context 'something was changed' do
      before do
        @updated_at = contest.updated_at = DateTime.now - 1.day
        round.votes.each { |v| v.finished_on = Date.yesterday }
        contest.process!
      end

      it { contest.updated_at.should_not eq @updated_at }
    end

    context 'nothing was changed' do
      before do
        @updated_at = contest.updated_at = DateTime.now - 1.day
        contest.process!
      end

      it { contest.updated_at.should eq @updated_at }
    end
  end

  describe :current_round do
    let(:contest) { create :contest_with_5_animes }
    before { contest.prepare }

    it 'first round' do
      contest.current_round.should eq contest.rounds.first
    end

    it 'started round' do
      contest.rounds[1].stub(:started?).and_return true
      contest.current_round.should eq contest.rounds.second
    end

    it 'first created' do
      contest.rounds[0].stub(:finished?).and_return true
      contest.current_round.should eq contest.rounds.second
    end

    it 'last round' do
      contest.state = 'finished'
      contest.current_round.should eq contest.rounds.last
    end
  end

  describe :defeated_by do
    let(:contest) { create :contest }
    let(:round) { create :contest_round, contest_id: contest.id }

    before do
      @entries = [
        create(:anime),
        create(:anime),
        create(:anime),
        create(:anime),
        create(:anime)
      ]
      create :contest_vote, round: round, left: @entries[0], right: @entries[1], winner_id: @entries[1].id, state: 'finished'
      create :contest_vote, round: round, left: @entries[0], right: @entries[2], winner_id: @entries[0].id, state: 'finished'
      create :contest_vote, round: round, left: @entries[0], right: @entries[3], winner_id: @entries[3].id, state: 'finished'
      create :contest_vote, round: round, left: @entries[0], right: @entries[4], winner_id: @entries[0].id, state: 'finished'
    end

    it 'returns defeated entries' do
      contest.defeated_by(@entries[0]).map(&:id).should eq [@entries[2].id, @entries[4].id]
    end
  end

  describe :user_vote_key do
    subject { contest.user_vote_key }
    let(:contest) { create :contest, user_vote_key: vote_key }

    describe 'can_vote_1' do
      let(:vote_key) { 'can_vote_1' }
      it { should eq 'can_vote_1' }
    end

    describe 'can_vote_2' do
      let(:vote_key) { 'can_vote_2' }
      it { should eq 'can_vote_2' }
    end

    describe 'wrong key' do
      let(:vote_key) { 'can_vote_2' }
      before { contest.user_vote_key = 'login' }
      it { should be_nil }
    end
  end

  describe :strategy do
    subject { create :contest, strategy_type: strategy_type }

    context :double_elimination do
      let(:strategy_type) { :double_elimination }
      its(:strategy) { should be_kind_of Contest::DoubleEliminationStrategy }
    end

    context :play_off do
      let(:strategy_type) { :play_off }
      its(:strategy) { should be_kind_of Contest::PlayOffStrategy }
    end
  end

  context '#class methods' do
    describe :current do
      subject { Contest.current.map(&:id) }

      context 'nothing' do
        let!(:contest) { create :contest }
        it { should eq [] }
      end

      context 'finished not so long ago' do
        let!(:contest) { create :contest, state: 'finished', finished_on: Date.today - 6.days }
        it { should eq [contest.id] }

        context 'new one started' do
          let!(:contest2) { create :contest, state: 'started' }
          it { should eq [contest.id, contest2.id] }

          context 'and one more started' do
            let!(:contest3) { create :contest, state: 'started' }
            it { should eq [contest.id, contest2.id, contest3.id] }
          end
        end
      end

      context 'finished long ago' do
        let!(:contest) { create :contest, state: 'finished', finished_on: Date.today - 8.days }
        it { should be_empty }

        context 'new one started' do
          let!(:contest) { contest = create :contest, state: 'started' }
          it { should eq [contest.id] }
        end
      end
    end
  end
end
