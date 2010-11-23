class Symbol

  def to_snake!
    self.to_s.dup.to_snake!.to_sym
  end

  def to_camel!
    self.to_s.dup.to_camel!.to_sym
  end
end