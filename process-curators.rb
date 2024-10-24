# curator details (tab-delimited):
# 0 name,
# 1 email address,
# 2 available operating systems,
# 3 optional notes,
# 4 whether they have a controller available
curators_file = "input/curators.tsv"

# game details (tab-delimited):
# 0 title,
# 1 download link or other details,
# 2 single-use keys,
# 3 operating systems game can run on,
# 4 whether the game requires a controller,
# 5 whether the game is strictly multiplayer
games_file = "input/games.tsv"

# process curators

@curators = {}

File.readlines(curators_file, chomp: true).drop(1).each do |line|
  name, email, platforms, junk, has_controller = line.split(/\t/)
  
  # make sure that curators who are harder to match up get first pick (e.g. users only running Linux)
  weight = 1
  if !platforms.include?("Windows")
    weight += 1
    if !platforms.include?("MacOS")
      weight += 1
    end
  end
    
  @curators[name] = { email: email, platforms: platforms, has_controller: has_controller, weight: weight }
end

@curators = @curators.sort_by { | k,v | -v[:weight] }.to_h

# process games

@games = {}

File.readlines(games_file, chomp: true).drop(1).each do |line|
  columns = line.split(/\t/)

  title, link, keys, platforms = columns[0..3]

  needs_controller = columns[4] == "yes"
  if needs_controller
    link += "** The developer has indicated that this game requires a controller."
  end

  multiplayer_only = columns[5] == "yes"
  if multiplayer_only
    link += "** This game requires at least two players."
  end

  # likewise, games that are harder (or easier) to match up should be weighted appropriately
  weight = 1
  weight += 1 if needs_controller
  weight -= 1 if platforms.include?("Web")
  
  @games[title] = { link: link, keys: keys.split(/\s/), platforms: platforms, needs_controller: needs_controller, weight: weight }  
end

@games = @games.sort_by { | k,v | -v[:weight] }.to_h

# we might have hardcoded some match ups because Reasons

def initialize_assignments
  assignments_file = "input/assignments.tsv"
  
  assignments_by_curator = {}

  @curators.keys.each do | name |
    assignments_by_curator[name] = []
  end
  
  if File.file?(assignments_file)
    File.readlines(assignments_file, chomp: true).drop(1).each do |line|
      columns = line.split(/\t/)

      title = columns[0]
      curators = columns[1..-1]
  
      curators.each do | name |
        assignments_by_curator[name.strip] << title.strip
      end
    end    
  end
  return assignments_by_curator
end

# fill the remaining slots with appropriate/still-available curators

def generate_assignments(assignments_by_curator, curators_per_game, games_per_curator)  
  @games.each do | title, details |
    game_platforms = details[:platforms].split(', ')
  
    count = assignments_by_curator.values.flatten.count(title)
    curators_needed = curators_per_game - count
    next if curators_needed == 0
    
    potential_curators = []
    
    @curators.each do | name, info |
      # curator has been assigned the maximum number (or more!) of games
      next if assignments_by_curator[name].count >= games_per_curator
      # curator has already been assigned to this game
      next if assignments_by_curator[name].include?(title)
      # anyone can play web-based games, but otherwise disqualify curators without the appropriate software
      next unless game_platforms.include?("Web") || (game_platforms & info[:platforms].split(', ')).size > 0
      # curator doesn't have a controller for a game that absolutely, positively needs one
      next if details[:needs_controller] && info[:has_controller] != "Yes"

      potential_curators << name
    end

    # we don't have enough curators, which probably means something is wrong
    if potential_curators.count < curators_needed
      return {}
    end
    
    potential_curators.first(curators_needed).each do | name |
      assignments_by_curator[name] << title
    end
  end

  @all_conditions_satisfied = true
  return assignments_by_curator
end

curators_per_game = 3
games_per_curator = 4

puts "Generating assignments"
assignments_by_curator = initialize_assignments
assignments_by_curator = generate_assignments(assignments_by_curator, curators_per_game, games_per_curator)

output_merge_file = "output/merge.tsv"
output_simple_file = "output/simple.tsv"

File.open(output_merge_file, "w") {}
File.open(output_simple_file, "w") {}

unless assignments_by_curator.empty?
  assignments_by_curator.sort.to_h.each do | name, games |
    line = [name, @curators[name][:email]]
    games.each do | title |
      line += [title, @games[title][:link], @games[title][:keys].shift]
    end
    File.write(output_merge_file, line.join("\t")+"\n",  mode: 'a')

    line = [name] + games
    File.write(output_simple_file, line.join("\t")+"\n",  mode: 'a')
  end
else
  puts "Giving up..."
end
