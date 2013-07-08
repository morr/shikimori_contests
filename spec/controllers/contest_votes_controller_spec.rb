require 'spec_helper'

describe ContestVotesController do
  let(:vote) { create :contest_vote, state: 'started' }

  describe :show do
    before { get :show, contest_id: vote.contest_round.contest_id, id: vote.id }
    it { should respond_with 200 }
  end

  describe :vote do
    let(:user) { create :user }
    before { sign_in user }

    context 'new vote' do
      before { post :vote, contest_id: vote.contest_round.contest_id, id: vote.id, variant: 'left' }

      it { should respond_with 200 }
      it { should respond_with_content_type :json }
      it { assigns(:vote).user_votes.should have(1).item }
    end

    context 'has user_id vote' do
      before do
        vote.vote_for 'left', user, '123'
        post :vote, contest_id: vote.contest_round.contest_id, id: vote.id, variant: 'right'
      end
      let(:json) { JSON.parse response.body }

      it { should respond_with 200 }
      it { should respond_with_content_type :json }
      it { assigns(:vote).user_votes.should have(1).item }
      it { json['variant'].should eq 'right' }
      it { json['vote_id'].should eq vote.id }
    end

    context 'has ip vote' do
      before do
        vote.vote_for 'left', create(:user), '0.0.0.0'
        post :vote, contest_id: vote.contest_round.contest_id, id: vote.id, variant: 'right'
      end

      it { should respond_with 422 }
      it { should respond_with_content_type :json }
      it { assigns(:vote).user_votes.should have(1).item }
    end
  end
end
