# Just a little script to do the curator ~ submissions matchup, e.g. for a small indie games festival
# Adri - Oct 23 2024
# Updated Nov 12 2025

CURATORS_PER_GAME = 3
GAMES_PER_CURATOR = 5

## INPUT

# curator details:
# [name, email address, available platforms, do they have a controller?, do they have a Steam account?]
curators_file = "input/curators.tsv"

# game details: [title, description, three_words, download/web link, single-use keys, other details,
# platforms game can run on, is a controller required?, is Steam required?
# (optionally) is the game strictly  multiplayer?]
games_file = "input/games.tsv"

# hardcoded matchups: [title, name+] OR [name, title+]
assignments_file = "input/assignments.tsv"

## OUTPUT

# details to share with curators
# see: https://developers.google.com/apps-script/samples/automations/mail-merge
# [curator name, curator's email address, (game title, game details/link, (e.g. Steam) key)+]
mail_merge_file = "output/mail_merge.tsv"

# just the basic details: [curator name, game title*]
basic_details_file = "output/assignments.tsv"

## read in the curator details and store in a hash by curator name
def process_curators(curators_file)
  curators = {}
  
  File.readlines(curators_file, chomp: true).drop(1).each do |line|
    name, email, platforms, has_controller, has_steam = line.split(/\t/)

    # make sure that curators who are harder to match up get first pick
    weight = (["Windows", "MacOS"] & platforms.split(", ")).count
    if !platforms.include?("Windows")
      weight -= 1
      if !platforms.include?("MacOS")
        weight -= 1
      end
    end

    first_name = name.split(' ').first
    
    curators[name.strip] = { first_name: first_name, email: email, platforms: platforms, has_controller: has_controller, has_steam: has_steam, weight: weight }
  end

  curators = curators.sort_by { | k,v | v[:weight] }.to_h

  return curators
end

## read in the submission details and store in a hash by game title
def process_games(games_file)
  games = {}

  File.readlines(games_file, chomp: true).drop(1).each do |line|
    columns = line.split(/\t/)

    title, description, three_words, link, keys, notes, platforms = columns[0..6]

    needs_controller = columns[7] == "yes"
    if needs_controller
      notes += " The developer has indicated that this game requires a controller."
    end

    needs_steam = columns[8] == "Yes"

#    multiplayer_only = columns[9] == "yes"
#    if multiplayer_only
#      notes += ' This game requires at least two players.'
#    end
    
    # games that are harder (or easier) to match up should be weighted appropriately
    weight = 1
    weight += 1 if needs_controller
    weight -= 1 if platforms.include?("Web")
  
    games[title.strip] = { description: description, three_words: three_words, link: link, keys: keys.split(/ /), notes: notes.strip,
                           platforms: platforms, needs_controller: needs_controller, needs_steam: needs_steam, weight: weight }    
  end

  games = games.sort_by { | k,v | -v[:weight] }.to_h

  return games
end

## we might have done some pre-matching of curators to games, because Reasons
def initialize_assignments(assignments_file)
  assignments_by_curator = {}
  
  @curators.keys.each do | name |
    assignments_by_curator[name] = []
  end

  if File.exist?(assignments_file)
    line = File.open(assignments_file, &:gets)
    key = line.split(/\t/).first

    return initialize_assignments_by_curator(assignments_file, assignments_by_curator) if key == "Name"
    return initialize_assignments_by_game(assignments_file, assignments_by_curator) if key == "Game Title"
  end
  
  return assignments_by_curator
end

def initialize_assignments_by_curator(assignments_file, assignments_by_curator)
  File.readlines(assignments_file, chomp: true).drop(1).each do |line|
    columns = line.split(/\t/)

    curator = columns[0]
    games = columns[1..-1]
    
    games.each do | title |
      # clean up input so it matches spreadsheet data
      assignments_by_curator[curator.strip] << title.strip
    end
  end    

  return assignments_by_curator
end

def initialize_assignments_by_game(assignments_file, assignments_by_curator)  
  File.readlines(assignments_file, chomp: true).drop(1).each do |line|
    columns = line.split(/\t/)

    title = columns[0]
    curators = columns[1..-1]
    
    curators.each do | name |
      # clean up input so it matches spreadsheet data
      assignments_by_curator[name.strip] << title.strip
    end
  end    

  return assignments_by_curator
end

## fill the remaining slots with appropriate (and still-available) curators
def generate_assignments(assignments_by_curator, pass = 0, games = @games)
  unfulfilled_games = {}
  
  games.each do | title, details |
    game_platforms = details[:platforms].split(', ')
  
    curators_assigned = assignments_by_curator.values.flatten.count(title)
    curators_needed = CURATORS_PER_GAME - curators_assigned
    next if curators_needed == 0
    
    potential_curators = []
    
    @curators.each do | name, info |
      # curator has been assigned the maximum number (or more!) of games
      next if assignments_by_curator[name].count >= GAMES_PER_CURATOR + pass
      # curator has already been assigned to this game
      next if assignments_by_curator[name].include?(title)
      # anyone can play web-based games, but otherwise disqualify curators without the appropriate software
      next unless game_platforms.include?("Web") || (game_platforms & info[:platforms].split(', ')).size > 0
      # curator doesn't have a controller for a game that absolutely, positively needs one
      next if details[:needs_controller] && info[:has_controller] != "Yes"
      # curator doesn't have a Steam account for a game that requires one
      next if details[:needs_steam] && info[:has_steam] != "Yes"
      potential_curators << name
    end
    
    # we don't have enough curators, so we'll need to make a second pass
    if potential_curators.count < curators_needed
      unfulfilled_games[title] = details
    end

    potential_curators.first(curators_needed).each do | name |
      assignments_by_curator[name] << title
    end
  end

  return assignments_by_curator, unfulfilled_games
end


# TODO
def create_output_files(assignments_by_curator, mail_merge_file, basic_details_file)
  # if files already exist, zero them out before appending new data
  File.open(mail_merge_file, "w") {}
  File.open(basic_details_file, "w") {}

  if assignments_by_curator.empty?
    puts "No assignments made."
    return
  end

  assignments_by_curator.sort.to_h.each do | name, games |
    line = [@curators[name][:first_name], @curators[name][:email]]
    games.each do | title |
      game = @games[title]
      line += [title, "\"#{game[:description]}\"", game[:three_words], "\"#{game[:link]}\"", game[:keys].shift, "\"#{game[:notes]}\""]
    end
    File.write(mail_merge_file, line.join("\t")+"\n",  mode: 'a')
    
    line = [name] + games
    File.write(basic_details_file, line.join("\t")+"\n",  mode: 'a')
  end
end

###

@curators = process_curators(curators_file)
@games = process_games(games_file)

assignments_by_curator = initialize_assignments(assignments_file)

unfulfilled_games = @games
pass = 0
while unfulfilled_games.size > 0 do
  assignments_by_curator, unfulfilled_games = generate_assignments(assignments_by_curator, pass, unfulfilled_games)
  pass += 1
end

create_output_files(assignments_by_curator, mail_merge_file, basic_details_file)
