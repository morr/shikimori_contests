class ContestVote < ActiveRecord::Base
  Undefined = 'undefined variant'

  belongs_to :contest_round
  belongs_to :left, :polymorphic => true
  belongs_to :right, :polymorphic => true
  has_many :contest_user_votes
  has_many :user_votes, :class_name => ContestUserVote.name,
                        :dependent => :destroy

  scope :with_user_vote, lambda { |user, ip|
    if user
      joins("left join #{ContestUserVote.table_name} cuv on cuv.contest_vote_id=`#{table_name}`.`id` and (cuv.id is null or cuv.user_id=#{sanitize user.id} or cuv.ip=#{sanitize ip})")
        .select("`#{table_name}`.*, !isnull(cuv.item_id) as voted")
    end
  }

  state_machine :state, :initial => :created do
    state :created do
      def can_vote?
        false
      end
    end

    state :started do
      def can_vote?
        true
      end

      # голосование за конкретный вариант
      def vote_for(variant, user, ip)
        user_votes.where(user_id: user.id).delete_all
        user_votes.create! user_id: user.id, item_id: variant.to_s == 'none' ? 0 : send("#{variant}_id"), ip: ip
      end

      # обновление статуса пользоваетля в зависимости от возможности голосовать далее
      def update_user(user, ip)
        if contest_round.votes.with_user_vote(user, ip).select(&:started?).all?(&:voted?)
          user.update_attribute contest_round.contest.user_vote_key, false
        end
      end
    end

    state :finished do
      def can_vote?
        false
      end

      # победитель
      def winner
        if winner_id == left_id
          left
        else
          right
        end
      end

      # проигравший
      def loser
        if winner_id == left_id
          right
        else
          left
        end
      end
    end

    event :start do
      transition :created => :started, :if => lambda { |vote| vote.started_on <= Date.today }
    end
    event :finish do
      transition :started => :finished, :if => lambda { |vote| vote.finished_on < Date.today }
    end

    after_transition :created => :started do |vote, transition|
      User.update_all vote.contest_round.contest.user_vote_key => true

      if vote.right.nil?
        vote.right = nil
        vote.save!

      elsif vote.left.nil? && vote.right.present?
        vote.left = vote.right
        vote.right = nil
        vote.save!
      end
    end

    after_transition :started => :finished do |vote, transition|
      winner_id = if vote.right_id.nil?
        vote.left_id

      elsif vote.left_votes > vote.right_votes
        vote.left_id

      elsif vote.right_votes > vote.left_votes
        vote.right_id

      elsif vote.left.score > vote.right.score
        vote.left_id

      elsif vote.right.score > vote.left.score
        vote.right_id

      else
        vote.left_id
      end

      vote.update_attribute :winner_id, winner_id

      # продвижение вперед победителя
      vote.contest_round.advance_winner vote.winner, vote.group
      # продвижение вперед проигравшего
      vote.contest_round.advance_loser vote.loser, vote.group if vote.loser
    end
  end

  # за какой вариант проголосовал пользователь
  def voted_for?(user, user_ip)
    return unless user

    user_vote = user_votes.where { user_id.eq(user.id) | ip.eq(user_ip) }.first
    if user_vote
      if user_vote.item_id == left_id
        :left
      elsif user_vote.item_id == right_id
        :right
      else
        :none
      end
    else
      nil
    end
  end

  # за какой вариант проголосовал пользователь (работает при выборке со scope with_user_vote)
  def voted?
    self['voted'] == 1 || (right_type.nil? && self['voted'] == 0)
  end

  # состояние с учётом голоса текущего пользователя
  def state_with_voted
    if started?
      voted? ? 'voted' : 'pending'
    elsif finished?
      'finished'
    else
      'created'
    end
  end

  # число голосов за левого кандидата
  def left_votes
    @left_votes ||= contest_user_votes.where(item_id: left_id).count
  end

  # число голосов за правого кандидата
  def right_votes
    @right_votes ||= contest_user_votes.where(item_id: right_id).count
  end

  # число голосов за правого кандидата
  def refrained_votes
    @refrained_votes ||= contest_user_votes.where(item_id: 0).count
  end
end
