class ContestVotesController < ApplicationController
  before_filter :authenticate_user!, :only => [:vote]
  layout nil

  def show
    @vote = ContestVote.find params[:id]
    render partial: 'contest_votes/contest_vote', object: @vote, formats: :html
  end

  def vote
    @vote = ContestVote.find params[:id]
    @vote.vote_for params[:variant], current_user, remote_addr
    @vote.update_user current_user, remote_addr

    render json: {
      vote_id: @vote.id,
      variant: params[:variant]
    }
  rescue ActiveRecord::RecordNotUnique => e
    render :json => ['С вашего IP адреса здесь уже проголосовали'], :status => :unprocessable_entity
  end
end
