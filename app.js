/* ============================================
   BUZZABOO - Next-Gen Live Streaming Platform
   Main Application JavaScript
   ============================================ */

// ============================================
// MOCK DATA - 50+ Streamers
// ============================================

const STREAMERS = [
  { id: 1, username: "NinjaVortex", displayName: "NinjaVortex", avatar: "https://i.pravatar.cc/150?img=1", banner: "https://picsum.photos/seed/banner1/1200/400", bio: "Professional esports player & content creator. 10x Tournament Champion. Living the dream one stream at a time! 🎮", followers: 2847563, verified: true, partner: true, socials: { twitter: "ninjavortex", instagram: "ninjavortex", youtube: "NinjaVortex" } },
  { id: 2, username: "LunaStarlight", displayName: "Luna ✨", avatar: "https://i.pravatar.cc/150?img=5", banner: "https://picsum.photos/seed/banner2/1200/400", bio: "Variety streamer & digital artist. Creating magical moments daily! Art commissions open 🎨", followers: 1523890, verified: true, partner: true, socials: { twitter: "lunastarlight", instagram: "luna.starlight" } },
  { id: 3, username: "TechWizard", displayName: "TechWizard", avatar: "https://i.pravatar.cc/150?img=3", banner: "https://picsum.photos/seed/banner3/1200/400", bio: "Software engineer by day, variety streamer by night. Let's learn and game together! 💻", followers: 892456, verified: true, partner: true, socials: { twitter: "techwiz", youtube: "TechWizardTV" } },
  { id: 4, username: "MelodyMaven", displayName: "Melody 🎵", avatar: "https://i.pravatar.cc/150?img=9", banner: "https://picsum.photos/seed/banner4/1200/400", bio: "Singer, songwriter, producer. Original music & covers every stream! Debut album coming 2026 🎤", followers: 2156789, verified: true, partner: true, socials: { spotify: "melodymaven", instagram: "melodymaven" } },
  { id: 5, username: "GhostRider", displayName: "GhostRider", avatar: "https://i.pravatar.cc/150?img=7", banner: "https://picsum.photos/seed/banner5/1200/400", bio: "Horror game specialist. I play what you're too scared to! 👻 Streams at midnight PST", followers: 756234, verified: true, partner: false, socials: { twitter: "ghostrider_live" } },
  { id: 6, username: "SpeedDemon", displayName: "SpeedDemon 🏎️", avatar: "https://i.pravatar.cc/150?img=11", banner: "https://picsum.photos/seed/banner6/1200/400", bio: "World record speedrunner. If it has a timer, I'll break it! Current WR holder in 12 games", followers: 1456789, verified: true, partner: true, socials: { twitter: "speeddemon", youtube: "SpeedDemonRuns" } },
  { id: 7, username: "ChefRamsay", displayName: "Chef Ramsay", avatar: "https://i.pravatar.cc/150?img=12", banner: "https://picsum.photos/seed/banner7/1200/400", bio: "Professional chef cooking up a storm! Learn gourmet recipes with me. Cookbook available now! 👨‍🍳", followers: 934521, verified: true, partner: true, socials: { instagram: "cheframsay_live", youtube: "ChefRamsayLive" } },
  { id: 8, username: "ArtisticSoul", displayName: "Artistic Soul", avatar: "https://i.pravatar.cc/150?img=16", banner: "https://picsum.photos/seed/banner8/1200/400", bio: "Digital artist & illustrator. Watch art come to life! Commissions: artisticsoul.com 🖼️", followers: 567890, verified: false, partner: false, socials: { twitter: "artisticsoul", instagram: "artistic.soul" } },
  { id: 9, username: "ProGamerX", displayName: "ProGamer X", avatar: "https://i.pravatar.cc/150?img=15", banner: "https://picsum.photos/seed/banner9/1200/400", bio: "FPS specialist. Former pro player. Coaching sessions available! Educational gaming content 🎯", followers: 2345678, verified: true, partner: true, socials: { twitter: "progamerx", discord: "progamerx" } },
  { id: 10, username: "CozyVibes", displayName: "Cozy Vibes 🌸", avatar: "https://i.pravatar.cc/150?img=20", banner: "https://picsum.photos/seed/banner10/1200/400", bio: "ASMR, cozy games, and good vibes only. Your safe space on the internet ☕", followers: 1234567, verified: true, partner: true, socials: { twitter: "cozyvibes", tiktok: "cozyvibes" } },
  { id: 11, username: "ShadowNinja", displayName: "Shadow Ninja", avatar: "https://i.pravatar.cc/150?img=33", banner: "https://picsum.photos/seed/banner11/1200/400", bio: "Stealth game expert. 100% completion or bust! Patience is my weapon 🥷", followers: 456789, verified: false, partner: true, socials: { twitter: "shadowninja_ttv" } },
  { id: 12, username: "PixelPrincess", displayName: "Pixel Princess", avatar: "https://i.pravatar.cc/150?img=25", banner: "https://picsum.photos/seed/banner12/1200/400", bio: "Retro gaming enthusiast. NES to PS5, I play it all! Nostalgia trips every weekend 🕹️", followers: 678901, verified: true, partner: true, socials: { twitter: "pixelprincess", youtube: "PixelPrincessGaming" } },
  { id: 13, username: "BassDropKing", displayName: "BassDropKing", avatar: "https://i.pravatar.cc/150?img=52", banner: "https://picsum.photos/seed/banner13/1200/400", bio: "DJ & music producer. Live sets every Friday! Releasing new EP next month 🎧", followers: 1567890, verified: true, partner: true, socials: { soundcloud: "bassdropking", spotify: "bassdropking" } },
  { id: 14, username: "YogaWithMia", displayName: "Yoga with Mia", avatar: "https://i.pravatar.cc/150?img=26", banner: "https://picsum.photos/seed/banner14/1200/400", bio: "Certified yoga instructor. Daily sessions for all levels. Find your zen! 🧘‍♀️", followers: 789012, verified: true, partner: true, socials: { instagram: "yogawithmia", youtube: "YogaWithMia" } },
  { id: 15, username: "CryptoKid", displayName: "CryptoKid", avatar: "https://i.pravatar.cc/150?img=57", banner: "https://picsum.photos/seed/banner15/1200/400", bio: "Web3 builder & educator. Making crypto simple for everyone. Not financial advice! 📈", followers: 345678, verified: true, partner: false, socials: { twitter: "cryptokid_live" } },
  { id: 16, username: "StarCraft_Legend", displayName: "SC Legend", avatar: "https://i.pravatar.cc/150?img=60", banner: "https://picsum.photos/seed/banner16/1200/400", bio: "Former StarCraft pro. Still got it! Strategy games are life ⭐", followers: 890123, verified: true, partner: true, socials: { twitter: "sclegend", discord: "sclegend" } },
  { id: 17, username: "MakeupQueen", displayName: "Makeup Queen 👑", avatar: "https://i.pravatar.cc/150?img=27", banner: "https://picsum.photos/seed/banner17/1200/400", bio: "Beauty guru & makeup artist. Transform with me! Brand collabs: DM me 💄", followers: 2456789, verified: true, partner: true, socials: { instagram: "makeupqueen", tiktok: "makeupqueen" } },
  { id: 18, username: "FitnessFrank", displayName: "Fitness Frank", avatar: "https://i.pravatar.cc/150?img=53", banner: "https://picsum.photos/seed/banner18/1200/400", bio: "Personal trainer. Live workouts daily! No excuses, just results 💪", followers: 567890, verified: true, partner: true, socials: { instagram: "fitnessfrank", youtube: "FitnessFrankLive" } },
  { id: 19, username: "ChessGrandmaster", displayName: "GM Fischer", avatar: "https://i.pravatar.cc/150?img=58", banner: "https://picsum.photos/seed/banner19/1200/400", bio: "International Chess Master. Teaching chess to the masses! Rated 2650+ ♟️", followers: 1234567, verified: true, partner: true, socials: { twitter: "gmfischer", chess: "GMFischer" } },
  { id: 20, username: "VRPioneer", displayName: "VR Pioneer", avatar: "https://i.pravatar.cc/150?img=59", banner: "https://picsum.photos/seed/banner20/1200/400", bio: "Virtual reality explorer. Testing the future every day! 🥽", followers: 456789, verified: true, partner: true, socials: { twitter: "vrpioneer", youtube: "VRPioneerTV" } },
  { id: 21, username: "BakingBetty", displayName: "Baking Betty", avatar: "https://i.pravatar.cc/150?img=28", banner: "https://picsum.photos/seed/banner21/1200/400", bio: "Home baker extraordinaire. Sweet treats and good eats! Recipe book coming soon 🧁", followers: 678901, verified: true, partner: true, socials: { instagram: "bakingbetty", pinterest: "bakingbetty" } },
  { id: 22, username: "RocketLeaguer", displayName: "Rocket Master", avatar: "https://i.pravatar.cc/150?img=61", banner: "https://picsum.photos/seed/banner22/1200/400", bio: "SSL in Rocket League. Road to pro! Coaching available 🚀", followers: 890123, verified: true, partner: true, socials: { twitter: "rocketmaster", discord: "rocketmaster" } },
  { id: 23, username: "PoetrySlam", displayName: "Poetry Slam", avatar: "https://i.pravatar.cc/150?img=29", banner: "https://picsum.photos/seed/banner23/1200/400", bio: "Spoken word artist. Words that move you. New book 'Midnight Thoughts' out now 📝", followers: 234567, verified: false, partner: false, socials: { twitter: "poetryslam_live" } },
  { id: 24, username: "MinecraftMaster", displayName: "MC Master", avatar: "https://i.pravatar.cc/150?img=62", banner: "https://picsum.photos/seed/banner24/1200/400", bio: "Building amazing worlds in Minecraft! Server owner. 5000+ hours played ⛏️", followers: 3456789, verified: true, partner: true, socials: { twitter: "mcmaster", youtube: "MinecraftMasterTV" } },
  { id: 25, username: "JustDancing", displayName: "Just Dancing 💃", avatar: "https://i.pravatar.cc/150?img=30", banner: "https://picsum.photos/seed/banner25/1200/400", bio: "Professional dancer. Hip-hop, contemporary, everything! Dance tutorials weekly", followers: 1567890, verified: true, partner: true, socials: { instagram: "justdancing", tiktok: "justdancing" } },
  { id: 26, username: "ScienceSteve", displayName: "Science Steve", avatar: "https://i.pravatar.cc/150?img=63", banner: "https://picsum.photos/seed/banner26/1200/400", bio: "Physics PhD making science fun! Experiments, explanations, explosions! 🔬", followers: 789012, verified: true, partner: true, socials: { twitter: "sciencesteve", youtube: "ScienceSteveTV" } },
  { id: 27, username: "CardMagician", displayName: "Card Magician", avatar: "https://i.pravatar.cc/150?img=64", banner: "https://picsum.photos/seed/banner27/1200/400", bio: "Professional magician. Card tricks, illusions, and mind-bending magic! 🎩", followers: 456789, verified: true, partner: true, socials: { instagram: "cardmagician", youtube: "CardMagicianTV" } },
  { id: 28, username: "WildlifeWatcher", displayName: "Wildlife Watcher", avatar: "https://i.pravatar.cc/150?img=65", banner: "https://picsum.photos/seed/banner28/1200/400", bio: "Nature photographer streaming from the wild! Live animal encounters 🦁", followers: 567890, verified: true, partner: true, socials: { twitter: "wildlifewatcher", instagram: "wildlife.watcher" } },
  { id: 29, username: "ASMRQueen", displayName: "ASMR Queen 🌙", avatar: "https://i.pravatar.cc/150?img=31", banner: "https://picsum.photos/seed/banner29/1200/400", bio: "Tingles guaranteed! Relaxation, sleep streams, and peaceful vibes only ✨", followers: 2345678, verified: true, partner: true, socials: { youtube: "ASMRQueenOfficial", instagram: "asmrqueen" } },
  { id: 30, username: "TabletopKing", displayName: "Tabletop King", avatar: "https://i.pravatar.cc/150?img=66", banner: "https://picsum.photos/seed/banner30/1200/400", bio: "D&D dungeon master. Board games, RPGs, and epic adventures! Roll for initiative! 🎲", followers: 678901, verified: true, partner: true, socials: { twitter: "tabletopking", discord: "tabletopking" } },
  { id: 31, username: "CarGuy", displayName: "Car Guy 🏎️", avatar: "https://i.pravatar.cc/150?img=67", banner: "https://picsum.photos/seed/banner31/1200/400", bio: "Automotive enthusiast. Sim racing, car shows, and engine sounds! Petrolhead for life", followers: 890123, verified: true, partner: true, socials: { instagram: "carguy_live", youtube: "CarGuyTV" } },
  { id: 32, username: "PianoProdigy", displayName: "Piano Prodigy", avatar: "https://i.pravatar.cc/150?img=32", banner: "https://picsum.photos/seed/banner32/1200/400", bio: "Classical pianist. Taking requests! From Chopin to modern hits 🎹", followers: 1234567, verified: true, partner: true, socials: { spotify: "pianoprodigy", youtube: "PianoProdigyLive" } },
  { id: 33, username: "FortniteKing", displayName: "Fortnite King", avatar: "https://i.pravatar.cc/150?img=68", banner: "https://picsum.photos/seed/banner33/1200/400", bio: "Top 100 Fortnite player. Victory Royales daily! Building like no other 🏆", followers: 4567890, verified: true, partner: true, socials: { twitter: "fortniteking", youtube: "FortniteKingTV" } },
  { id: 34, username: "KnitNinja", displayName: "Knit Ninja 🧶", avatar: "https://i.pravatar.cc/150?img=34", banner: "https://picsum.photos/seed/banner34/1200/400", bio: "Knitting & crocheting streams. Cozy crafting vibes! Patterns on Etsy", followers: 234567, verified: false, partner: true, socials: { etsy: "knitninja", instagram: "knit.ninja" } },
  { id: 35, username: "WarzoneWarrior", displayName: "Warzone Warrior", avatar: "https://i.pravatar.cc/150?img=69", banner: "https://picsum.photos/seed/banner35/1200/400", bio: "Call of Duty specialist. High kill games daily! 500+ wins this season 🔫", followers: 2345678, verified: true, partner: true, socials: { twitter: "warzonewarrior", youtube: "WarzoneWarriorTV" } },
  { id: 36, username: "GuitarHero", displayName: "Guitar Hero 🎸", avatar: "https://i.pravatar.cc/150?img=70", banner: "https://picsum.photos/seed/banner36/1200/400", bio: "Shredding since '99! Rock, metal, blues - I play it all. Lessons available!", followers: 1567890, verified: true, partner: true, socials: { instagram: "guitarhero_live", youtube: "GuitarHeroLive" } },
  { id: 37, username: "CosplayQueen", displayName: "Cosplay Queen", avatar: "https://i.pravatar.cc/150?img=35", banner: "https://picsum.photos/seed/banner37/1200/400", bio: "Award-winning cosplayer. Making costumes live! Con schedule on my website 👸", followers: 1890123, verified: true, partner: true, socials: { instagram: "cosplayqueen", tiktok: "cosplayqueen" } },
  { id: 38, username: "PhilosophyNerd", displayName: "Philosophy Nerd", avatar: "https://i.pravatar.cc/150?img=71", banner: "https://picsum.photos/seed/banner38/1200/400", bio: "Let's discuss the big questions! Philosophy degree put to good use 🤔", followers: 345678, verified: false, partner: true, socials: { twitter: "philosophynerd" } },
  { id: 39, username: "ValheimViking", displayName: "Valheim Viking", avatar: "https://i.pravatar.cc/150?img=72", banner: "https://picsum.photos/seed/banner39/1200/400", bio: "Survival game enthusiast. Building epic bases! ⚔️ SKÅL!", followers: 567890, verified: true, partner: true, socials: { twitter: "valheimviking", discord: "valheimviking" } },
  { id: 40, username: "TravelWithTina", displayName: "Travel with Tina", avatar: "https://i.pravatar.cc/150?img=36", banner: "https://picsum.photos/seed/banner40/1200/400", bio: "IRL streams from around the world! Currently: Tokyo 🗼 50 countries and counting!", followers: 2456789, verified: true, partner: true, socials: { instagram: "travelwithtina", youtube: "TravelWithTinaTV" } },
  { id: 41, username: "ApexPredator", displayName: "Apex Predator", avatar: "https://i.pravatar.cc/150?img=73", banner: "https://picsum.photos/seed/banner41/1200/400", bio: "Apex Legends ranked grinder. Predator every split! Tips and gameplay daily 🎯", followers: 1234567, verified: true, partner: true, socials: { twitter: "apexpredator_ttv", youtube: "ApexPredatorTV" } },
  { id: 42, username: "MovieBuff", displayName: "Movie Buff 🎬", avatar: "https://i.pravatar.cc/150?img=74", banner: "https://picsum.photos/seed/banner42/1200/400", bio: "Film critic & watch-along host. New releases, classics, hidden gems!", followers: 678901, verified: true, partner: true, socials: { twitter: "moviebuff_live", letterboxd: "moviebuff" } },
  { id: 43, username: "LeagueOfLegends", displayName: "LoL Legend", avatar: "https://i.pravatar.cc/150?img=75", banner: "https://picsum.photos/seed/banner43/1200/400", bio: "Challenger player every season. Educational League content! 🏆", followers: 3456789, verified: true, partner: true, socials: { twitter: "lollegend", youtube: "LoLLegendTV" } },
  { id: 44, username: "PlantMom", displayName: "Plant Mom 🌱", avatar: "https://i.pravatar.cc/150?img=37", banner: "https://picsum.photos/seed/banner44/1200/400", bio: "300+ plants in my jungle! Indoor gardening tips, repotting streams, plant care ❤️", followers: 456789, verified: true, partner: true, socials: { instagram: "plantmom_live", tiktok: "plantmom" } },
  { id: 45, username: "StreamerDad", displayName: "Streamer Dad", avatar: "https://i.pravatar.cc/150?img=76", banner: "https://picsum.photos/seed/banner45/1200/400", bio: "Dad by day, gamer by night! Family-friendly content. The kids sometimes crash my stream 👨‍👧‍👦", followers: 890123, verified: true, partner: true, socials: { twitter: "streamerdad", youtube: "StreamerDadTV" } },
  { id: 46, username: "ValorantViper", displayName: "Valorant Viper", avatar: "https://i.pravatar.cc/150?img=38", banner: "https://picsum.photos/seed/banner46/1200/400", bio: "Immortal rank Valorant player. Viper main! Agent guides and ranked games 🐍", followers: 2345678, verified: true, partner: true, socials: { twitter: "valorantviper", youtube: "ValorantViperTV" } },
  { id: 47, username: "BookWorm", displayName: "Book Worm 📚", avatar: "https://i.pravatar.cc/150?img=39", banner: "https://picsum.photos/seed/banner47/1200/400", bio: "Live reading sessions, book reviews, and literary discussions! 100 books/year challenge", followers: 345678, verified: false, partner: true, socials: { goodreads: "bookworm", instagram: "bookworm_reads" } },
  { id: 48, username: "DrumMachine", displayName: "Drum Machine", avatar: "https://i.pravatar.cc/150?img=77", banner: "https://picsum.photos/seed/banner48/1200/400", bio: "Professional drummer. Session musician. Taking song requests! 🥁", followers: 567890, verified: true, partner: true, socials: { instagram: "drummachine", youtube: "DrumMachineLive" } },
  { id: 49, username: "PokerPro", displayName: "Poker Pro", avatar: "https://i.pravatar.cc/150?img=78", banner: "https://picsum.photos/seed/banner49/1200/400", bio: "Professional poker player. Strategy streams & tournament runs! $2M+ lifetime winnings 🃏", followers: 1234567, verified: true, partner: true, socials: { twitter: "pokerpro_live", youtube: "PokerProTV" } },
  { id: 50, username: "AnimeExpert", displayName: "Anime Expert", avatar: "https://i.pravatar.cc/150?img=40", banner: "https://picsum.photos/seed/banner50/1200/400", bio: "Anime reviewer & manga reader. Watch-alongs, discussions, and reactions! 🍥", followers: 2456789, verified: true, partner: true, socials: { twitter: "animeexpert", youtube: "AnimeExpertTV" } },
  { id: 51, username: "CodingLive", displayName: "Coding Live", avatar: "https://i.pravatar.cc/150?img=79", banner: "https://picsum.photos/seed/banner51/1200/400", bio: "Full-stack dev building cool stuff! Learn to code with me 💻", followers: 678901, verified: true, partner: true, socials: { github: "codinglive", twitter: "codinglive" } },
  { id: 52, username: "SoccerStar", displayName: "Soccer Star ⚽", avatar: "https://i.pravatar.cc/150?img=80", banner: "https://picsum.photos/seed/banner52/1200/400", bio: "EA FC & real soccer analysis. Former semi-pro player! Match breakdowns daily", followers: 890123, verified: true, partner: true, socials: { twitter: "soccerstar_live", instagram: "soccerstar" } }
];

// Live streams (currently live)
const LIVE_STREAMS = [
  { streamerId: 1, title: "🔴 ROAD TO GLOBAL! CSGO RANKED GRIND | !giveaway !discord", game: "Counter-Strike 2", viewers: 45672, startedAt: new Date(Date.now() - 3600000 * 2.5), tags: ["English", "FPS", "Ranked", "Giveaway"], thumbnail: "https://picsum.photos/seed/stream1/640/360" },
  { streamerId: 2, title: "✨ Chill art stream! Drawing your suggestions 🎨 | !socials", game: "Art", viewers: 12456, startedAt: new Date(Date.now() - 3600000 * 4), tags: ["English", "Art", "Creative", "Chill"], thumbnail: "https://picsum.photos/seed/stream2/640/360" },
  { streamerId: 4, title: "🎵 Late night acoustic session | Taking requests! 🎤", game: "Music", viewers: 28934, startedAt: new Date(Date.now() - 3600000 * 1.5), tags: ["English", "Music", "Acoustic", "Requests"], thumbnail: "https://picsum.photos/seed/stream4/640/360" },
  { streamerId: 6, title: "SPEEDRUN ATTEMPTS - Elden Ring Any% | Current PB: 23:45", game: "Elden Ring", viewers: 34521, startedAt: new Date(Date.now() - 3600000 * 5), tags: ["English", "Speedrun", "SoulsLike"], thumbnail: "https://picsum.photos/seed/stream6/640/360" },
  { streamerId: 9, title: "🎯 VALORANT RADIANT GAMEPLAY | Educational Commentary", game: "Valorant", viewers: 67890, startedAt: new Date(Date.now() - 3600000 * 3), tags: ["English", "FPS", "Educational", "Ranked"], thumbnail: "https://picsum.photos/seed/stream9/640/360" },
  { streamerId: 10, title: "☕ Cozy Sunday vibes | Stardew Valley & chill | !playlist", game: "Stardew Valley", viewers: 18234, startedAt: new Date(Date.now() - 3600000 * 6), tags: ["English", "Cozy", "Chill", "Farming"], thumbnail: "https://picsum.photos/seed/stream10/640/360" },
  { streamerId: 13, title: "🎧 FRIDAY NIGHT LIVE DJ SET | EDM/House/DnB", game: "Music", viewers: 42156, startedAt: new Date(Date.now() - 3600000 * 2), tags: ["English", "Music", "DJ", "EDM"], thumbnail: "https://picsum.photos/seed/stream13/640/360" },
  { streamerId: 17, title: "💄 Get ready with me! New products review | !giveaway", game: "Just Chatting", viewers: 31245, startedAt: new Date(Date.now() - 3600000 * 1), tags: ["English", "Beauty", "GRWM", "Giveaway"], thumbnail: "https://picsum.photos/seed/stream17/640/360" },
  { streamerId: 19, title: "♟️ Chess.com Arena | Playing viewers | !challenge", game: "Chess", viewers: 15678, startedAt: new Date(Date.now() - 3600000 * 4.5), tags: ["English", "Chess", "Strategy", "Interactive"], thumbnail: "https://picsum.photos/seed/stream19/640/360" },
  { streamerId: 24, title: "⛏️ BUILDING A MEGA BASE | Survival SMP Day 847", game: "Minecraft", viewers: 89012, startedAt: new Date(Date.now() - 3600000 * 7), tags: ["English", "Minecraft", "Building", "Survival"], thumbnail: "https://picsum.photos/seed/stream24/640/360" },
  { streamerId: 25, title: "💃 Learning a NEW CHOREOGRAPHY | !tiktok !insta", game: "Just Chatting", viewers: 22345, startedAt: new Date(Date.now() - 3600000 * 0.5), tags: ["English", "Dance", "Tutorial"], thumbnail: "https://picsum.photos/seed/stream25/640/360" },
  { streamerId: 29, title: "🌙 ASMR Sleep Stream | Gentle whispers & triggers ✨", game: "ASMR", viewers: 54321, startedAt: new Date(Date.now() - 3600000 * 8), tags: ["English", "ASMR", "Sleep", "Relaxation"], thumbnail: "https://picsum.photos/seed/stream29/640/360" },
  { streamerId: 33, title: "🏆 FORTNITE RANKED GRIND | Road to Unreal | !code", game: "Fortnite", viewers: 123456, startedAt: new Date(Date.now() - 3600000 * 3.5), tags: ["English", "Fortnite", "Ranked", "Battle Royale"], thumbnail: "https://picsum.photos/seed/stream33/640/360" },
  { streamerId: 35, title: "🔫 WARZONE 3 REBIRTH ISLAND | High Kill Games", game: "Call of Duty: Warzone", viewers: 78901, startedAt: new Date(Date.now() - 3600000 * 2), tags: ["English", "FPS", "Battle Royale"], thumbnail: "https://picsum.photos/seed/stream35/640/360" },
  { streamerId: 40, title: "🗼 IRL TOKYO STREAM | Exploring Shibuya! | !location", game: "IRL", viewers: 45678, startedAt: new Date(Date.now() - 3600000 * 1.5), tags: ["English", "IRL", "Travel", "Japan"], thumbnail: "https://picsum.photos/seed/stream40/640/360" },
  { streamerId: 41, title: "🎯 APEX LEGENDS PRED RANKED | Solo Queue Pain", game: "Apex Legends", viewers: 34567, startedAt: new Date(Date.now() - 3600000 * 4), tags: ["English", "FPS", "Ranked", "Battle Royale"], thumbnail: "https://picsum.photos/seed/stream41/640/360" },
  { streamerId: 43, title: "🏆 LEAGUE OF LEGENDS CHALLENGER | Jungle Main", game: "League of Legends", viewers: 98765, startedAt: new Date(Date.now() - 3600000 * 5), tags: ["English", "MOBA", "Ranked"], thumbnail: "https://picsum.photos/seed/stream43/640/360" },
  { streamerId: 46, title: "🐍 VALORANT RADIANT VIPER GAMEPLAY | Tips & Tricks", game: "Valorant", viewers: 56789, startedAt: new Date(Date.now() - 3600000 * 2.5), tags: ["English", "FPS", "Educational"], thumbnail: "https://picsum.photos/seed/stream46/640/360" },
  { streamerId: 50, title: "🍥 ANIME WATCH-ALONG | One Piece Marathon pt. 5", game: "Watch Party", viewers: 67890, startedAt: new Date(Date.now() - 3600000 * 6), tags: ["English", "Anime", "Watch Party"], thumbnail: "https://picsum.photos/seed/stream50/640/360" },
  { streamerId: 51, title: "💻 Building a SAAS App LIVE | Day 3 | !github", game: "Software Development", viewers: 12345, startedAt: new Date(Date.now() - 3600000 * 3), tags: ["English", "Coding", "Educational"], thumbnail: "https://picsum.photos/seed/stream51/640/360" }
];

// Categories
const CATEGORIES = [
  { id: 1, name: "Just Chatting", viewers: 1245678, image: "https://picsum.photos/seed/cat1/300/400", tags: ["IRL", "Talk Show"] },
  { id: 2, name: "Fortnite", viewers: 456789, image: "https://picsum.photos/seed/cat2/300/400", tags: ["Battle Royale", "Shooter"] },
  { id: 3, name: "League of Legends", viewers: 398765, image: "https://picsum.photos/seed/cat3/300/400", tags: ["MOBA", "Esports"] },
  { id: 4, name: "Valorant", viewers: 345678, image: "https://picsum.photos/seed/cat4/300/400", tags: ["FPS", "Tactical"] },
  { id: 5, name: "Minecraft", viewers: 312456, image: "https://picsum.photos/seed/cat5/300/400", tags: ["Sandbox", "Survival"] },
  { id: 6, name: "Grand Theft Auto V", viewers: 287654, image: "https://picsum.photos/seed/cat6/300/400", tags: ["RP", "Action"] },
  { id: 7, name: "Counter-Strike 2", viewers: 265432, image: "https://picsum.photos/seed/cat7/300/400", tags: ["FPS", "Esports"] },
  { id: 8, name: "Call of Duty: Warzone", viewers: 234567, image: "https://picsum.photos/seed/cat8/300/400", tags: ["Battle Royale", "FPS"] },
  { id: 9, name: "Apex Legends", viewers: 198765, image: "https://picsum.photos/seed/cat9/300/400", tags: ["Battle Royale", "FPS"] },
  { id: 10, name: "Music", viewers: 176543, image: "https://picsum.photos/seed/cat10/300/400", tags: ["Creative", "Performance"] },
  { id: 11, name: "Art", viewers: 154321, image: "https://picsum.photos/seed/cat11/300/400", tags: ["Creative", "Digital Art"] },
  { id: 12, name: "World of Warcraft", viewers: 143210, image: "https://picsum.photos/seed/cat12/300/400", tags: ["MMORPG", "Fantasy"] },
  { id: 13, name: "Dota 2", viewers: 132109, image: "https://picsum.photos/seed/cat13/300/400", tags: ["MOBA", "Esports"] },
  { id: 14, name: "ASMR", viewers: 121098, image: "https://picsum.photos/seed/cat14/300/400", tags: ["IRL", "Relaxation"] },
  { id: 15, name: "Elden Ring", viewers: 109876, image: "https://picsum.photos/seed/cat15/300/400", tags: ["RPG", "Souls-like"] },
  { id: 16, name: "IRL", viewers: 98765, image: "https://picsum.photos/seed/cat16/300/400", tags: ["Real Life", "Outdoors"] },
  { id: 17, name: "EA FC 25", viewers: 87654, image: "https://picsum.photos/seed/cat17/300/400", tags: ["Sports", "Soccer"] },
  { id: 18, name: "Stardew Valley", viewers: 76543, image: "https://picsum.photos/seed/cat18/300/400", tags: ["Indie", "Farming Sim"] },
  { id: 19, name: "Chess", viewers: 65432, image: "https://picsum.photos/seed/cat19/300/400", tags: ["Strategy", "Board Game"] },
  { id: 20, name: "Poker", viewers: 54321, image: "https://picsum.photos/seed/cat20/300/400", tags: ["Card Game", "Casino"] },
  { id: 21, name: "Watch Party", viewers: 43210, image: "https://picsum.photos/seed/cat21/300/400", tags: ["Movies", "Anime"] },
  { id: 22, name: "Software Development", viewers: 32109, image: "https://picsum.photos/seed/cat22/300/400", tags: ["Coding", "Educational"] }
];

// Chat messages pool
const CHAT_MESSAGES = [
  "PogChamp let's gooooo!!!",
  "This is insane gameplay!",
  "First time here, love the vibes!",
  "lmao that was hilarious 😂",
  "GG EZ",
  "Can someone explain what just happened?",
  "KEKW",
  "Let's get those W's!",
  "Been following for 3 years now!",
  "This stream is fire 🔥",
  "Drop your predictions below!",
  "Who else is watching at 3am? 😴",
  "@streamer you're the best!",
  "CLIP THAT!",
  "Gave a sub to spread the love ❤️",
  "The content today is S-tier",
  "New viewer here, instant follow!",
  "That play was absolutely insane",
  "Everyone spam hearts ❤️❤️❤️",
  "Reminder to stay hydrated! 💧",
  "Can we hit 1000 likes?",
  "Weekend streams hit different",
  "Best community on the platform!",
  "Song name?",
  "!discord link please",
  "Just dropped a sub bomb 💣",
  "This chat is moving so fast",
  "Certified hood classic",
  "My streamer 😤",
  "GOAT status confirmed 🐐"
];

const CHAT_USERNAMES = [
  "XxGamerxX", "StreamFan99", "NightOwl2026", "ChillVibes", "LuckyUser", 
  "ProWatcher", "SilentLurker", "HypeTrain", "MemeLord", "EpicGamer",
  "StreamEnjoyer", "LateNighter", "CasualFan", "SuperMod", "ViewerOne",
  "TheRealFan", "StreamSupporter", "PogChampion", "NicePerson", "RegularViewer"
];

// ============================================
// UTILITY FUNCTIONS
// ============================================

function formatNumber(num) {
  if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
  if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
  return num.toString();
}

function formatDuration(startTime) {
  const diff = Date.now() - new Date(startTime).getTime();
  const hours = Math.floor(diff / 3600000);
  const minutes = Math.floor((diff % 3600000) / 60000);
  return `${hours}:${minutes.toString().padStart(2, '0')}`;
}

function formatTimeAgo(date) {
  const seconds = Math.floor((Date.now() - new Date(date).getTime()) / 1000);
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return Math.floor(seconds / 60) + 'm ago';
  if (seconds < 86400) return Math.floor(seconds / 3600) + 'h ago';
  return Math.floor(seconds / 86400) + 'd ago';
}

function getStreamer(id) {
  return STREAMERS.find(s => s.id === id);
}

function getRandomItem(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function shuffleArray(arr) {
  const newArr = [...arr];
  for (let i = newArr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [newArr[i], newArr[j]] = [newArr[j], newArr[i]];
  }
  return newArr;
}

// ============================================
// THEME MANAGEMENT
// ============================================

const Theme = {
  init() {
    const saved = localStorage.getItem('buzzaboo-theme') || 'dark';
    this.set(saved);
    this.bindToggle();
  },
  
  set(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('buzzaboo-theme', theme);
    const icon = document.querySelector('.theme-toggle-icon');
    if (icon) {
      icon.textContent = theme === 'dark' ? '🌙' : '☀️';
    }
  },
  
  toggle() {
    const current = document.documentElement.getAttribute('data-theme');
    this.set(current === 'dark' ? 'light' : 'dark');
  },
  
  bindToggle() {
    document.querySelectorAll('.theme-toggle').forEach(btn => {
      btn.addEventListener('click', () => this.toggle());
    });
  }
};

// ============================================
// SEARCH FUNCTIONALITY
// ============================================

const Search = {
  init() {
    const searchInput = document.querySelector('.search-bar input');
    if (searchInput) {
      searchInput.addEventListener('input', (e) => this.handleSearch(e.target.value));
      searchInput.addEventListener('focus', () => this.showResults());
      document.addEventListener('click', (e) => {
        if (!e.target.closest('.search-container')) {
          this.hideResults();
        }
      });
    }
  },
  
  handleSearch(query) {
    if (query.length < 2) {
      this.hideResults();
      return;
    }
    
    const results = this.search(query);
    this.renderResults(results);
  },
  
  search(query) {
    const q = query.toLowerCase();
    const streamers = STREAMERS.filter(s => 
      s.username.toLowerCase().includes(q) || 
      s.displayName.toLowerCase().includes(q)
    ).slice(0, 5);
    
    const categories = CATEGORIES.filter(c => 
      c.name.toLowerCase().includes(q)
    ).slice(0, 3);
    
    return { streamers, categories };
  },
  
  renderResults(results) {
    let container = document.querySelector('.search-results');
    if (!container) {
      container = document.createElement('div');
      container.className = 'search-results';
      document.querySelector('.search-container')?.appendChild(container);
    }
    
    let html = '';
    
    if (results.streamers.length > 0) {
      html += '<div class="search-section"><div class="search-section-title">Channels</div>';
      results.streamers.forEach(s => {
        const isLive = LIVE_STREAMS.some(ls => ls.streamerId === s.id);
        html += `
          <a href="profile.html?user=${s.username}" class="search-result-item">
            <img src="${s.avatar}" alt="${s.displayName}" class="search-result-avatar">
            <div class="search-result-info">
              <div class="search-result-name">${s.displayName}</div>
              <div class="search-result-meta">${isLive ? '🔴 Live' : formatNumber(s.followers) + ' followers'}</div>
            </div>
          </a>
        `;
      });
      html += '</div>';
    }
    
    if (results.categories.length > 0) {
      html += '<div class="search-section"><div class="search-section-title">Categories</div>';
      results.categories.forEach(c => {
        html += `
          <a href="browse.html?category=${c.id}" class="search-result-item">
            <img src="${c.image}" alt="${c.name}" class="search-result-avatar" style="border-radius: 6px;">
            <div class="search-result-info">
              <div class="search-result-name">${c.name}</div>
              <div class="search-result-meta">${formatNumber(c.viewers)} viewers</div>
            </div>
          </a>
        `;
      });
      html += '</div>';
    }
    
    container.innerHTML = html || '<div class="search-no-results">No results found</div>';
    container.style.display = 'block';
  },
  
  showResults() {
    const container = document.querySelector('.search-results');
    if (container && container.innerHTML) {
      container.style.display = 'block';
    }
  },
  
  hideResults() {
    const container = document.querySelector('.search-results');
    if (container) {
      container.style.display = 'none';
    }
  }
};

// ============================================
// CHAT SYSTEM
// ============================================

const Chat = {
  messages: [],
  interval: null,
  
  init(containerId) {
    this.container = document.getElementById(containerId);
    if (!this.container) return;
    
    this.messagesEl = this.container.querySelector('.chat-messages');
    this.inputEl = this.container.querySelector('.chat-input');
    this.sendBtn = this.container.querySelector('.chat-send-btn');
    
    this.bindEvents();
    this.startSimulation();
  },
  
  bindEvents() {
    if (this.sendBtn) {
      this.sendBtn.addEventListener('click', () => this.sendMessage());
    }
    if (this.inputEl) {
      this.inputEl.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') this.sendMessage();
      });
    }
  },
  
  sendMessage() {
    const text = this.inputEl?.value.trim();
    if (!text) return;
    
    this.addMessage({
      username: 'You',
      text: text,
      isOwn: true,
      badges: ['sub']
    });
    
    this.inputEl.value = '';
  },
  
  addMessage(msg) {
    const msgEl = document.createElement('div');
    msgEl.className = 'chat-message' + (msg.isOwn ? ' own' : '');
    
    const badgeHtml = msg.badges?.map(b => `<span class="chat-badge ${b}">${this.getBadgeIcon(b)}</span>`).join('') || '';
    const userClass = msg.isOwn ? 'sub' : (Math.random() > 0.7 ? 'mod' : (Math.random() > 0.5 ? 'sub' : ''));
    
    msgEl.innerHTML = `
      <div class="chat-content">
        ${badgeHtml}
        <span class="chat-username ${userClass}">${msg.username}:</span>
        <span class="chat-text">${this.parseEmotes(msg.text)}</span>
      </div>
    `;
    
    this.messagesEl?.appendChild(msgEl);
    this.messagesEl?.scrollTo({ top: this.messagesEl.scrollHeight, behavior: 'smooth' });
    
    // Limit messages
    while (this.messagesEl?.children.length > 100) {
      this.messagesEl.removeChild(this.messagesEl.firstChild);
    }
  },
  
  getBadgeIcon(badge) {
    const icons = {
      mod: '🛡️',
      sub: '⭐',
      vip: '💎',
      verified: '✓'
    };
    return icons[badge] || '';
  },
  
  parseEmotes(text) {
    const emotes = {
      ':)': '😊',
      ':D': '😄',
      ':P': '😛',
      '<3': '❤️',
      'PogChamp': '😲',
      'KEKW': '😂',
      'Sadge': '😢',
      'LULW': '😆',
      'monkaS': '😰',
      'PepeHands': '😭'
    };
    
    let result = text;
    Object.keys(emotes).forEach(key => {
      result = result.replace(new RegExp(key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'), emotes[key]);
    });
    return result;
  },
  
  startSimulation() {
    this.interval = setInterval(() => {
      if (Math.random() > 0.3) {
        this.addMessage({
          username: getRandomItem(CHAT_USERNAMES),
          text: getRandomItem(CHAT_MESSAGES),
          badges: Math.random() > 0.7 ? [getRandomItem(['mod', 'sub', 'vip'])] : []
        });
      }
    }, 800 + Math.random() * 2000);
  },
  
  stop() {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }
};

// ============================================
// STREAM CARDS RENDERER
// ============================================

const StreamCards = {
  render(streams, containerId, limit = 20) {
    const container = document.getElementById(containerId);
    if (!container) return;
    
    const html = streams.slice(0, limit).map(stream => {
      const streamer = getStreamer(stream.streamerId);
      return `
        <a href="stream.html?channel=${streamer.username}" class="stream-card">
          <div class="stream-thumbnail-wrapper">
            <img src="${stream.thumbnail}" alt="${stream.title}" class="stream-thumbnail" loading="lazy">
            <div class="stream-overlay"></div>
            <span class="stream-live-badge">LIVE</span>
            <span class="stream-viewers">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z"/></svg>
              ${formatNumber(stream.viewers)}
            </span>
            <span class="stream-duration">${formatDuration(stream.startedAt)}</span>
          </div>
          <div class="stream-info">
            <div class="stream-header">
              <img src="${streamer.avatar}" alt="${streamer.displayName}" class="streamer-avatar">
              <div class="stream-details">
                <div class="stream-title">${stream.title}</div>
                <div class="streamer-name">${streamer.displayName}</div>
                <span class="stream-category">${stream.game}</span>
              </div>
            </div>
            <div class="stream-tags">
              ${stream.tags.slice(0, 3).map(t => `<span class="stream-tag">${t}</span>`).join('')}
            </div>
          </div>
        </a>
      `;
    }).join('');
    
    container.innerHTML = html;
  }
};

// ============================================
// CATEGORY CARDS RENDERER
// ============================================

const CategoryCards = {
  render(categories, containerId, limit = 12) {
    const container = document.getElementById(containerId);
    if (!container) return;
    
    const html = categories.slice(0, limit).map(cat => `
      <a href="browse.html?category=${cat.id}" class="category-card">
        <img src="${cat.image}" alt="${cat.name}" class="category-image" loading="lazy">
        <div class="category-overlay"></div>
        <div class="category-info">
          <div class="category-name">${cat.name}</div>
          <div class="category-viewers">${formatNumber(cat.viewers)} viewers</div>
        </div>
      </a>
    `).join('');
    
    container.innerHTML = html;
  }
};

// ============================================
// SIDEBAR
// ============================================

const Sidebar = {
  init() {
    this.render();
    this.bindToggle();
  },
  
  render() {
    const container = document.getElementById('sidebar-followed');
    if (!container) return;
    
    const liveStreamers = LIVE_STREAMS.map(s => ({
      ...getStreamer(s.streamerId),
      stream: s
    }));
    
    const html = liveStreamers.slice(0, 10).map(s => `
      <a href="stream.html?channel=${s.username}" class="sidebar-item">
        <div class="sidebar-item-avatar live">
          <img src="${s.avatar}" alt="${s.displayName}">
        </div>
        <div class="sidebar-item-info">
          <div class="sidebar-item-name">${s.displayName}</div>
          <div class="sidebar-item-game">${s.stream.game}</div>
        </div>
        <div class="sidebar-item-viewers">${formatNumber(s.stream.viewers)}</div>
      </a>
    `).join('');
    
    container.innerHTML = html;
  },
  
  bindToggle() {
    const toggle = document.querySelector('.sidebar-toggle');
    const sidebar = document.querySelector('.sidebar');
    
    if (toggle && sidebar) {
      toggle.addEventListener('click', () => {
        sidebar.classList.toggle('collapsed');
      });
    }
  }
};

// ============================================
// FEATURED STREAM
// ============================================

const FeaturedStream = {
  render(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;
    
    const featured = LIVE_STREAMS.reduce((max, s) => s.viewers > max.viewers ? s : max);
    const streamer = getStreamer(featured.streamerId);
    
    container.innerHTML = `
      <div class="featured-stream">
        <img src="${featured.thumbnail}" alt="${featured.title}" class="featured-thumbnail">
        <div class="featured-overlay"></div>
        <div class="featured-content">
          <span class="featured-badge">🔴 Featured Stream</span>
          <h2 class="featured-title">${featured.title}</h2>
          <div class="featured-streamer">
            <img src="${streamer.avatar}" alt="${streamer.displayName}">
            <div>
              <div class="featured-streamer-name">${streamer.displayName}</div>
              <div class="featured-streamer-game">${featured.game}</div>
            </div>
          </div>
          <div class="featured-stats">
            <div class="featured-stat">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5z"/></svg>
              ${formatNumber(featured.viewers)} watching
            </div>
            <div class="featured-stat">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zM12 20c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8zm.5-13H11v6l5.25 3.15.75-1.23-4.5-2.67z"/></svg>
              ${formatDuration(featured.startedAt)}
            </div>
          </div>
          <a href="stream.html?channel=${streamer.username}" class="btn btn-primary btn-lg">Watch Now</a>
        </div>
      </div>
    `;
  }
};

// ============================================
// MULTIVIEW
// ============================================

const Multiview = {
  streams: [],
  
  init() {
    this.container = document.getElementById('multiview-container');
    if (!this.container) return;
    
    this.render();
    this.bindEvents();
  },
  
  render() {
    const slots = 4;
    let html = '';
    
    for (let i = 0; i < slots; i++) {
      if (this.streams[i]) {
        const stream = this.streams[i];
        const streamer = getStreamer(stream.streamerId);
        html += `
          <div class="multiview-item" data-slot="${i}">
            <img src="${stream.thumbnail}" alt="${stream.title}" class="multiview-player">
            <div class="multiview-info">
              <div class="multiview-streamer">
                <img src="${streamer.avatar}" alt="${streamer.displayName}" width="30" height="30" style="border-radius: 50%;">
                <span>${streamer.displayName}</span>
              </div>
              <button class="multiview-close" data-slot="${i}">✕</button>
            </div>
          </div>
        `;
      } else {
        html += `
          <div class="multiview-item empty" data-slot="${i}">
            <div class="multiview-add">
              <div class="multiview-add-icon">+</div>
              <div>Add Stream</div>
            </div>
          </div>
        `;
      }
    }
    
    this.container.innerHTML = html;
  },
  
  bindEvents() {
    this.container.addEventListener('click', (e) => {
      const emptySlot = e.target.closest('.multiview-item.empty');
      if (emptySlot) {
        const slot = parseInt(emptySlot.dataset.slot);
        this.showStreamPicker(slot);
      }
      
      const closeBtn = e.target.closest('.multiview-close');
      if (closeBtn) {
        const slot = parseInt(closeBtn.dataset.slot);
        this.removeStream(slot);
      }
    });
  },
  
  showStreamPicker(slot) {
    const modal = document.createElement('div');
    modal.className = 'modal-overlay active';
    modal.innerHTML = `
      <div class="modal">
        <div class="modal-header">
          <h3 class="modal-title">Add Stream</h3>
          <button class="modal-close">✕</button>
        </div>
        <div class="modal-body">
          <div class="stream-picker-list">
            ${LIVE_STREAMS.filter(s => !this.streams.includes(s)).map(stream => {
              const streamer = getStreamer(stream.streamerId);
              return `
                <div class="stream-picker-item" data-stream-id="${stream.streamerId}">
                  <img src="${streamer.avatar}" alt="${streamer.displayName}">
                  <div>
                    <div style="font-weight: 600;">${streamer.displayName}</div>
                    <div style="font-size: 0.8rem; color: var(--text-secondary);">${stream.game} • ${formatNumber(stream.viewers)} viewers</div>
                  </div>
                </div>
              `;
            }).join('')}
          </div>
        </div>
      </div>
    `;
    
    document.body.appendChild(modal);
    
    modal.querySelector('.modal-close').addEventListener('click', () => modal.remove());
    modal.addEventListener('click', (e) => {
      if (e.target === modal) modal.remove();
      
      const item = e.target.closest('.stream-picker-item');
      if (item) {
        const streamerId = parseInt(item.dataset.streamId);
        const stream = LIVE_STREAMS.find(s => s.streamerId === streamerId);
        this.addStream(slot, stream);
        modal.remove();
      }
    });
  },
  
  addStream(slot, stream) {
    this.streams[slot] = stream;
    this.render();
    this.bindEvents();
  },
  
  removeStream(slot) {
    this.streams[slot] = null;
    this.render();
    this.bindEvents();
  }
};

// ============================================
// SHORTS / VERTICAL CLIPS
// ============================================

const Shorts = {
  clips: [],
  currentIndex: 0,
  
  init() {
    this.viewport = document.querySelector('.shorts-viewport');
    if (!this.viewport) return;
    
    this.generateClips();
    this.render();
    this.bindEvents();
  },
  
  generateClips() {
    this.clips = shuffleArray(LIVE_STREAMS).slice(0, 20).map((stream, i) => ({
      id: i,
      streamerId: stream.streamerId,
      title: `Epic ${stream.game} moment! #${i + 1}`,
      likes: Math.floor(Math.random() * 50000) + 1000,
      comments: Math.floor(Math.random() * 500) + 10,
      shares: Math.floor(Math.random() * 200) + 5,
      thumbnail: `https://picsum.photos/seed/short${i}/400/700`,
      tags: stream.tags.slice(0, 2)
    }));
  },
  
  render() {
    this.viewport.innerHTML = this.clips.map(clip => {
      const streamer = getStreamer(clip.streamerId);
      return `
        <div class="short-item" data-clip-id="${clip.id}">
          <img src="${clip.thumbnail}" alt="${clip.title}" class="short-video">
          <div class="short-overlay"></div>
          <div class="short-info">
            <div class="short-streamer">
              <img src="${streamer.avatar}" alt="${streamer.displayName}">
              <span class="short-streamer-name">${streamer.displayName}</span>
            </div>
            <div class="short-title">${clip.title}</div>
            <div class="short-tags">
              ${clip.tags.map(t => `<span class="short-tag">#${t}</span>`).join('')}
            </div>
          </div>
          <div class="short-actions">
            <div class="short-action" data-action="like">
              <div class="short-action-icon">❤️</div>
              <div class="short-action-count">${formatNumber(clip.likes)}</div>
            </div>
            <div class="short-action" data-action="comment">
              <div class="short-action-icon">💬</div>
              <div class="short-action-count">${formatNumber(clip.comments)}</div>
            </div>
            <div class="short-action" data-action="share">
              <div class="short-action-icon">↗️</div>
              <div class="short-action-count">${formatNumber(clip.shares)}</div>
            </div>
            <div class="short-action" data-action="follow">
              <div class="short-action-icon">➕</div>
              <div class="short-action-count">Follow</div>
            </div>
          </div>
        </div>
      `;
    }).join('');
  },
  
  bindEvents() {
    this.viewport.querySelectorAll('.short-action').forEach(action => {
      action.addEventListener('click', (e) => {
        const actionType = e.currentTarget.dataset.action;
        this.handleAction(actionType, e.currentTarget);
      });
    });
  },
  
  handleAction(type, el) {
    if (type === 'like') {
      el.classList.toggle('liked');
      const countEl = el.querySelector('.short-action-count');
      const current = parseInt(countEl.textContent.replace(/[^0-9]/g, ''));
      countEl.textContent = formatNumber(el.classList.contains('liked') ? current + 1 : current - 1);
    } else if (type === 'follow') {
      const countEl = el.querySelector('.short-action-count');
      countEl.textContent = countEl.textContent === 'Follow' ? 'Following' : 'Follow';
    }
  }
};

// ============================================
// DASHBOARD ANALYTICS
// ============================================

const Dashboard = {
  init() {
    this.renderStats();
    this.renderChart();
    this.renderRecentActivity();
  },
  
  renderStats() {
    const stats = [
      { label: 'Total Views', value: '2.4M', change: '+12.5%', positive: true, icon: '👁️' },
      { label: 'Followers', value: '156K', change: '+8.2%', positive: true, icon: '👥' },
      { label: 'Watch Hours', value: '48.2K', change: '+5.7%', positive: true, icon: '⏱️' },
      { label: 'Revenue', value: '$12,450', change: '+22.4%', positive: true, icon: '💰' }
    ];
    
    const container = document.getElementById('dashboard-stats');
    if (!container) return;
    
    container.innerHTML = stats.map(stat => `
      <div class="dashboard-card">
        <div class="dashboard-card-header">
          <span class="dashboard-card-title">${stat.label}</span>
          <div class="dashboard-card-icon">${stat.icon}</div>
        </div>
        <div class="dashboard-card-value">${stat.value}</div>
        <div class="dashboard-card-change ${stat.positive ? 'positive' : 'negative'}">
          ${stat.positive ? '↑' : '↓'} ${stat.change} vs last month
        </div>
      </div>
    `).join('');
  },
  
  renderChart() {
    const container = document.getElementById('dashboard-chart');
    if (!container) return;
    
    // Simplified chart visualization
    const data = [65, 78, 52, 91, 43, 85, 67, 72, 88, 95, 61, 79];
    const max = Math.max(...data);
    
    container.innerHTML = `
      <div class="chart-header">
        <h3 class="chart-title">Viewer Analytics</h3>
        <div class="chart-filters">
          <button class="chart-filter active">7D</button>
          <button class="chart-filter">30D</button>
          <button class="chart-filter">90D</button>
        </div>
      </div>
      <div style="display: flex; align-items: flex-end; gap: 8px; height: 300px; padding: 20px;">
        ${data.map((d, i) => `
          <div style="flex: 1; background: linear-gradient(180deg, var(--primary) 0%, var(--secondary) 100%); height: ${(d / max) * 100}%; border-radius: 4px 4px 0 0; opacity: 0.8; transition: opacity 0.3s;" onmouseover="this.style.opacity=1" onmouseout="this.style.opacity=0.8"></div>
        `).join('')}
      </div>
    `;
  },
  
  renderRecentActivity() {
    const container = document.getElementById('dashboard-activity');
    if (!container) return;
    
    const activities = [
      { type: 'follow', user: 'xXGamer99Xx', time: '2 min ago' },
      { type: 'sub', user: 'NightOwl2026', tier: 2, time: '5 min ago' },
      { type: 'donation', user: 'SuperFan', amount: '$25', time: '12 min ago' },
      { type: 'follow', user: 'NewViewer123', time: '15 min ago' },
      { type: 'sub', user: 'LoyalWatcher', tier: 1, time: '23 min ago' },
    ];
    
    container.innerHTML = `
      <h3 class="section-title">Recent Activity</h3>
      <div class="activity-list">
        ${activities.map(a => `
          <div class="activity-item" style="display: flex; align-items: center; gap: 12px; padding: 12px; background: var(--bg-glass); border-radius: 8px; margin-bottom: 8px;">
            <div style="width: 40px; height: 40px; border-radius: 50%; background: ${a.type === 'follow' ? 'var(--primary)' : a.type === 'sub' ? 'var(--secondary)' : 'var(--accent-green)'}; display: flex; align-items: center; justify-content: center;">
              ${a.type === 'follow' ? '👤' : a.type === 'sub' ? '⭐' : '💵'}
            </div>
            <div style="flex: 1;">
              <div style="font-weight: 600;">${a.user}</div>
              <div style="font-size: 0.8rem; color: var(--text-secondary);">
                ${a.type === 'follow' ? 'New follower' : a.type === 'sub' ? `Tier ${a.tier} subscription` : `Donated ${a.amount}`}
              </div>
            </div>
            <div style="font-size: 0.75rem; color: var(--text-muted);">${a.time}</div>
          </div>
        `).join('')}
      </div>
    `;
  }
};

// ============================================
// PROFILE PAGE
// ============================================

const Profile = {
  init() {
    const params = new URLSearchParams(window.location.search);
    const username = params.get('user') || 'NinjaVortex';
    
    const streamer = STREAMERS.find(s => s.username.toLowerCase() === username.toLowerCase()) || STREAMERS[0];
    const isLive = LIVE_STREAMS.some(s => s.streamerId === streamer.id);
    const stream = LIVE_STREAMS.find(s => s.streamerId === streamer.id);
    
    this.render(streamer, isLive, stream);
  },
  
  render(streamer, isLive, stream) {
    // Update header info
    document.querySelector('.profile-avatar')?.setAttribute('src', streamer.avatar);
    document.querySelector('.profile-name-text')?.textContent && (document.querySelector('.profile-name-text').textContent = streamer.displayName);
    document.querySelector('.profile-bio')?.textContent && (document.querySelector('.profile-bio').textContent = streamer.bio);
    
    // Update stats
    const statValues = document.querySelectorAll('.profile-stat-value');
    if (statValues.length >= 3) {
      statValues[0].textContent = formatNumber(streamer.followers);
      statValues[1].textContent = formatNumber(Math.floor(streamer.followers * 0.15));
      statValues[2].textContent = formatNumber(Math.floor(streamer.followers * 0.03));
    }
    
    // Show live indicator
    const liveIndicator = document.querySelector('.profile-live-indicator');
    if (liveIndicator) {
      liveIndicator.style.display = isLive ? 'block' : 'none';
    }
    
    // Render VODs
    this.renderVODs(streamer.id);
    
    // Render Clips
    this.renderClips(streamer.id);
  },
  
  renderVODs(streamerId) {
    const container = document.getElementById('profile-vods');
    if (!container) return;
    
    const vods = Array.from({ length: 6 }, (_, i) => ({
      id: i,
      title: `Past Broadcast ${i + 1} - Epic Gaming Session`,
      thumbnail: `https://picsum.photos/seed/vod${streamerId}${i}/400/225`,
      duration: `${Math.floor(Math.random() * 6) + 1}:${Math.floor(Math.random() * 60).toString().padStart(2, '0')}:${Math.floor(Math.random() * 60).toString().padStart(2, '0')}`,
      views: Math.floor(Math.random() * 50000) + 1000,
      date: new Date(Date.now() - Math.random() * 30 * 24 * 60 * 60 * 1000)
    }));
    
    container.innerHTML = vods.map(vod => `
      <div class="stream-card">
        <div class="stream-thumbnail-wrapper">
          <img src="${vod.thumbnail}" alt="${vod.title}" class="stream-thumbnail" loading="lazy">
          <span class="stream-duration">${vod.duration}</span>
        </div>
        <div class="stream-info">
          <div class="stream-title">${vod.title}</div>
          <div class="stream-meta" style="font-size: 0.8rem; color: var(--text-secondary);">
            ${formatNumber(vod.views)} views • ${formatTimeAgo(vod.date)}
          </div>
        </div>
      </div>
    `).join('');
  },
  
  renderClips(streamerId) {
    const container = document.getElementById('profile-clips');
    if (!container) return;
    
    const clips = Array.from({ length: 6 }, (_, i) => ({
      id: i,
      title: `Insane Clip #${i + 1} - Must Watch!`,
      thumbnail: `https://picsum.photos/seed/clip${streamerId}${i}/400/225`,
      duration: `0:${Math.floor(Math.random() * 50 + 10)}`,
      views: Math.floor(Math.random() * 100000) + 5000,
      date: new Date(Date.now() - Math.random() * 14 * 24 * 60 * 60 * 1000)
    }));
    
    container.innerHTML = clips.map(clip => `
      <div class="stream-card">
        <div class="stream-thumbnail-wrapper">
          <img src="${clip.thumbnail}" alt="${clip.title}" class="stream-thumbnail" loading="lazy">
          <span class="stream-duration">${clip.duration}</span>
        </div>
        <div class="stream-info">
          <div class="stream-title">${clip.title}</div>
          <div class="stream-meta" style="font-size: 0.8rem; color: var(--text-secondary);">
            ${formatNumber(clip.views)} views • ${formatTimeAgo(clip.date)}
          </div>
        </div>
      </div>
    `).join('');
  }
};

// ============================================
// STREAM PAGE
// ============================================

const StreamPage = {
  init() {
    const params = new URLSearchParams(window.location.search);
    const channel = params.get('channel') || 'NinjaVortex';
    
    const streamer = STREAMERS.find(s => s.username.toLowerCase() === channel.toLowerCase()) || STREAMERS[0];
    const stream = LIVE_STREAMS.find(s => s.streamerId === streamer.id) || LIVE_STREAMS[0];
    
    this.render(streamer, stream);
    Chat.init('chat-container');
    this.initPredictions();
    this.updateViewerCount(stream.viewers);
  },
  
  render(streamer, stream) {
    // Update page title
    document.title = `${streamer.displayName} - ${stream.title} | Buzzaboo`;
    
    // Update stream info
    const titleEl = document.querySelector('.stream-page-title');
    if (titleEl) titleEl.textContent = stream.title;
    
    const streamerEl = document.querySelector('.stream-page-streamer');
    if (streamerEl) {
      streamerEl.innerHTML = `
        <img src="${streamer.avatar}" alt="${streamer.displayName}" style="width: 50px; height: 50px; border-radius: 50%; border: 2px solid var(--primary);">
        <div>
          <div style="font-weight: 700; display: flex; align-items: center; gap: 6px;">
            ${streamer.displayName}
            ${streamer.verified ? '<span style="color: var(--primary);">✓</span>' : ''}
          </div>
          <div style="font-size: 0.85rem; color: var(--text-secondary);">${stream.game}</div>
        </div>
      `;
    }
    
    // Update viewer count
    const viewerEl = document.querySelector('.stream-viewer-count');
    if (viewerEl) {
      viewerEl.innerHTML = `
        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5z"/></svg>
        <span id="viewer-count">${formatNumber(stream.viewers)}</span> watching
      `;
    }
    
    // Set thumbnail as video placeholder
    const playerEl = document.querySelector('.player-video');
    if (playerEl) {
      playerEl.src = stream.thumbnail;
    }
  },
  
  initPredictions() {
    const container = document.getElementById('predictions-container');
    if (!container) return;
    
    container.innerHTML = `
      <div class="prediction-card">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px;">
          <span class="badge badge-primary">🎯 Active Prediction</span>
          <span style="font-size: 0.8rem; color: var(--text-secondary);">Ends in 2:45</span>
        </div>
        <div class="prediction-title">Will they win this match?</div>
        <div class="prediction-options">
          <div class="prediction-option" style="cursor: pointer;">
            <span>Yes 🏆</span>
            <div class="prediction-option-bar">
              <div class="prediction-option-fill blue" style="width: 65%;"></div>
            </div>
            <span style="font-weight: 600;">65%</span>
          </div>
          <div class="prediction-option" style="cursor: pointer;">
            <span>No 😢</span>
            <div class="prediction-option-bar">
              <div class="prediction-option-fill pink" style="width: 35%;"></div>
            </div>
            <span style="font-weight: 600;">35%</span>
          </div>
        </div>
        <div style="text-align: center; margin-top: 16px; font-size: 0.85rem; color: var(--text-secondary);">
          12,456 points in pool
        </div>
      </div>
    `;
  },
  
  updateViewerCount(base) {
    setInterval(() => {
      const change = Math.floor(Math.random() * 100) - 50;
      const newCount = Math.max(base + change, 100);
      const el = document.getElementById('viewer-count');
      if (el) el.textContent = formatNumber(newCount);
    }, 5000);
  }
};

// ============================================
// PWA SERVICE WORKER REGISTRATION
// ============================================

const PWA = {
  init() {
    if ('serviceWorker' in navigator) {
      window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js')
          .then(reg => console.log('SW registered:', reg.scope))
          .catch(err => console.log('SW registration failed:', err));
      });
    }
  }
};

// ============================================
// TOAST NOTIFICATIONS
// ============================================

const Toast = {
  container: null,
  
  init() {
    this.container = document.createElement('div');
    this.container.className = 'toast-container';
    document.body.appendChild(this.container);
  },
  
  show(type, title, message) {
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.innerHTML = `
      <div class="toast-icon">${type === 'success' ? '✓' : '✕'}</div>
      <div class="toast-content">
        <div class="toast-title">${title}</div>
        <div class="toast-message">${message}</div>
      </div>
      <div class="toast-close">✕</div>
    `;
    
    this.container.appendChild(toast);
    
    toast.querySelector('.toast-close').addEventListener('click', () => toast.remove());
    
    setTimeout(() => {
      toast.style.animation = 'toast-out 0.3s ease forwards';
      setTimeout(() => toast.remove(), 300);
    }, 5000);
  },
  
  success(title, message) {
    this.show('success', title, message);
  },
  
  error(title, message) {
    this.show('error', title, message);
  }
};

// ============================================
// MOBILE MENU
// ============================================

const MobileMenu = {
  init() {
    const toggle = document.querySelector('.mobile-menu-toggle');
    const sidebar = document.querySelector('.sidebar');
    
    if (toggle && sidebar) {
      toggle.addEventListener('click', () => {
        sidebar.classList.toggle('open');
      });
      
      // Close on outside click
      document.addEventListener('click', (e) => {
        if (!e.target.closest('.sidebar') && !e.target.closest('.mobile-menu-toggle')) {
          sidebar.classList.remove('open');
        }
      });
    }
  }
};

// ============================================
// DROPDOWN MENUS
// ============================================

const Dropdowns = {
  init() {
    document.querySelectorAll('.dropdown').forEach(dropdown => {
      const trigger = dropdown.querySelector('.dropdown-trigger');
      
      trigger?.addEventListener('click', (e) => {
        e.stopPropagation();
        
        // Close others
        document.querySelectorAll('.dropdown.active').forEach(d => {
          if (d !== dropdown) d.classList.remove('active');
        });
        
        dropdown.classList.toggle('active');
      });
    });
    
    // Close on outside click
    document.addEventListener('click', () => {
      document.querySelectorAll('.dropdown.active').forEach(d => d.classList.remove('active'));
    });
  }
};

// ============================================
// LAZY LOADING
// ============================================

const LazyLoad = {
  init() {
    if ('IntersectionObserver' in window) {
      const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            const img = entry.target;
            img.src = img.dataset.src;
            img.classList.remove('lazy');
            observer.unobserve(img);
          }
        });
      }, { rootMargin: '50px' });
      
      document.querySelectorAll('img.lazy').forEach(img => observer.observe(img));
    }
  }
};

// ============================================
// GLOBAL INITIALIZATION
// ============================================

document.addEventListener('DOMContentLoaded', () => {
  // Core
  Theme.init();
  Search.init();
  Toast.init();
  MobileMenu.init();
  Dropdowns.init();
  LazyLoad.init();
  PWA.init();
  
  // Page-specific
  const page = document.body.dataset.page;
  
  switch (page) {
    case 'home':
      Sidebar.init();
      FeaturedStream.render('featured-stream');
      StreamCards.render(shuffleArray(LIVE_STREAMS), 'live-streams', 12);
      CategoryCards.render(CATEGORIES, 'categories', 8);
      StreamCards.render(shuffleArray(LIVE_STREAMS), 'recommended-streams', 8);
      break;
      
    case 'browse':
      Sidebar.init();
      CategoryCards.render(CATEGORIES, 'all-categories', 24);
      StreamCards.render(shuffleArray(LIVE_STREAMS), 'category-streams', 20);
      break;
      
    case 'stream':
      StreamPage.init();
      break;
      
    case 'profile':
      Profile.init();
      break;
      
    case 'dashboard':
      Dashboard.init();
      break;
      
    case 'multiview':
      Multiview.init();
      break;
      
    case 'shorts':
      Shorts.init();
      break;
  }
});

// ============================================
// EXPORTS FOR GLOBAL ACCESS
// ============================================

window.Buzzaboo = {
  STREAMERS,
  LIVE_STREAMS,
  CATEGORIES,
  Theme,
  Search,
  Chat,
  Toast,
  formatNumber,
  formatDuration,
  getStreamer
};
