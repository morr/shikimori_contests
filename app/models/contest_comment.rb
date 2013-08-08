class ContestComment < AniMangaComment
  # текст топика
  def text
    self[:text] || "Топик [contest=#{self.linked_id}]опроса[/contest]."
  end

  def title
    "Опрос \"#{linked.title}\""
  end

  def to_s
    title
  end
end
