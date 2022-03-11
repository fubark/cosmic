// NOTE: This was ported from one of the first games made by fubar. 
// None of the algorithms or designs are recommended in your own games but it should at
// least show you how to use the Cosmic API.

// TODO: Use Cosmic UI when it's done.
// TODO: Reorganize code.

const Color = cs.graphics.Color
const TextAlign = cs.graphics.TextAlign
const TextBaseline = cs.graphics.TextBaseline
const AppName = 'paddleball'

const root = getMainScriptDir()

if (!cs.files.ensurePath(getAppDir(AppName))) {
    panic('Could not create app dir.')
}

class Game {
    static PWIDTH = 0
    static PHEIGHT = 0

    static BACKUP_PADDLE_Y = 0
    static ROOM_BOTTOM_Y = 0
    static SUPER_BGCHANGE_SPEED = 0.0003
    static NORMAL_BGCHANGE_SPEED = 0.00003
    static MINI_STAGE_Y = 210

    static MAINMENU = 0   // the main menu
    static GAME = 1       // the in game state
    static COLLECTION = 2 // shows all the levels you have completed
    static PRETEXT = 3    // the state just before the GAME state

    constructor() {
        this.bgChange = Game.NORMAL_BGCHANGE_SPEED

        this.gameState = false
        this.lastTimeMs = false
        this.done = false
        this.gameOver = false
        this.magiccover = 0 // how many magic covers on you
        this.magiccoverBounds = false
        this.isSuper = false

        this.powerups = false // good and bad
        this.greenitemCount = 0
        this.reditemCount = 0
        this.blueitemCount = 0
        this.whiteitemCount = 0
        this.yellowitemCount = 0 // can't get black ones because you die automatically

        this.mainPaddle = false
        this.balls = false
        this.ballCount = 0
        this.brickCount = 0

        // for super ball mode
        this.startTime = 0
        this.timePassed = 0
        this.startWatch = false

        this.count = 0.25; // for bgColor effect, don't want it to be 0 (too dark)
        this.hsvColor = []; // init for instance
        this.normalFont = 24
        this.titleFont = 60
        this.subtitleFont = 40
        this.subsubtitleFont = 30
        this.totalLevels = 0
        this.collection = false
        this.collectionSelectX = 20
        this.collectionSelectY = 120
        this.collectionSelectWidth = 180
        this.collectionSelectHeight = 40
        this.collectionSelect = 0
        this.collectionPlayButton = false
        this.collectionScores = false
        this.preText = false // ready? go!
        this.level = 0
        this.score = 0
        this.showScore = false
        this.tryAgainButton = false
        this.gameOverMenuButton = false
        this.scoreCount = 0 // used for an increasing displaying effect in the score screen
        this.whichScore = 0 // determines which score to show in the score screen
        this.totalScore = 0
        this.totalScoreCount = 0

        // used for an increasing displaying effect in the score screen
        this.greenitemScoreCount = 0
        this.reditemScoreCount = 0
        this.blueitemScoreCount = 0
        this.whiteitemScoreCount = 0
        this.yellowitemScoreCount = 0

        this.nextButton = false
        this.menuButton = false

        this.powerupCount = 0 // used for indice of the powerup array

        this.backupPaddle = false;

        this.inTransition = false;

        this.stageWinStreamId = 0

        this.hasSound = true;
        this.playButton = false;
        this.collectionButton = false;
        this.soundButton = false;

        this.countUp = true
        this.count = 0.25 // for bgColor effect, dont want it to be 0 (too dark)
        this.bricks = false
        this.scratchLine = {}
        this.BRICKS_WIDTH = 0
        this.BRICKS_HEIGHT = 0
    }

    initSize(width, height) {
        Game.PWIDTH = width
        Game.PHEIGHT = height
        Game.BRICKS_HEIGHT = Game.PHEIGHT / 30

        this.width = width
        this.height = height

        Game.BACKUP_PADDLE_Y = Game.PHEIGHT - 180
        Game.ROOM_BOTTOM_Y = Game.PHEIGHT - 100

        var buttonX = 20
        this.playButton = createButton('Play', buttonX, 230, Game.PWIDTH - 40, 70)
        this.collectionButton = createButton('', buttonX, 340, Game.PWIDTH - 40, 120)
        this.soundButton = createButton('', buttonX, 500, Game.PWIDTH - 40, 120)

        this.nextButton = createButton('Next Stage', buttonX, 600, Game.PWIDTH - 40, 70);
        this.menuButton = createButton('Menu', buttonX, 710, Game.PWIDTH - 40, 70);

        this.tryAgainButton = createButton('Try Again!', buttonX, Game.PHEIGHT / 2, Game.PWIDTH - 40, 70);
        this.gameOverMenuButton = createButton('Menu', buttonX, Game.PHEIGHT / 2 + 70 + 40, Game.PWIDTH - 40, 70);

        const miniMapScale = 2
        this.collectionPlayButton = createButton('Play', Game.PWIDTH/2 - 40, Game.MINI_STAGE_Y + Game.PHEIGHT / miniMapScale + 60, Game.PWIDTH / miniMapScale, 70);
    }

    init(width, height) {
        this.initSize(width, height)

        // Game.sound.init(4);
        Game.sound.load();
        this.gameState = Game.MAINMENU

        this.transitions = new Transitions(this)

        this.findLevels()
        var i
        this.collection = []
        for (i = 0; i < this.totalLevels; i++) {
            this.collection[i] = false
        }
        this.collectionScores = Game.persistence.getHighscores()

        // unlock levels
        for (i = 0; i < this.collectionScores.length; i++) {
            this.collection[i] = true
            if (this.collectionScores[i] == 0) {
                break
            }
        }

        //SoundManager.loopMusic(R.raw.menu);

        this.hasSound = Game.persistence.getSound()
        if (this.hasSound) {
            Game.sound.enable()
        } else {
            Game.sound.disable()
        }

        this.startGame()
    }

    endBall(ball) {
        if (!ball.dead) {
            this.ballCount -= 1
            ball.dead = true
        }
    }

    startLoop() {
        this.done = false
        this.lastTimeMs = new Date().getTime()
    }

    start() {
        this.level = 0
        this.loadLevel(this.level + 1)
    }

    findLevels() {
        this.totalLevels = Game.resources.getTotalLevels()
        this.collectionSelect = 0
    }

    restartLastTime() {
        this.lastTimeMs = new Date().getTime()
    }

    stop() {
        this.done = true
    }

    startGame() {
        this.gameOver = false
    }

    update(deltaMs) {
        var i
        // processTouchEvents
        if (this.inTransition) {
            return
        }
        if (this.gameState != Game.GAME) {
            return
        }
        if (this.gameOver) {
            return
        }
        this.updateBgColor(deltaMs)

        for (i = 0; i < this.powerups.length; i++) {
            var powerup = this.powerups[i]
            if (!powerup) {
                continue
            }
            if (powerup.dead) {
                continue
            }

            // powerups interaction with magic covers
            if (this.magiccover > 0) {
                if (powerup.type == Game.powerup.SIZE_DOWN) {
                    if (Game.misc.boundsIntersect(this.magiccoverBounds, powerup.bounds)) {
                        powerup.dead = true
                        this.magiccover--
                    }
                } else if (powerup.type == Game.powerup.DEATH_BOMB) {
                    if (Game.misc.boundsIntersect(this.magiccoverBounds, powerup.bounds)) {
                        powerup.dead = true
                        this.magiccover--
                    }
                }
            }

            powerup.update(deltaMs)

            if (Game.misc.boundsIntersect(this.mainPaddle.bounds, powerup.bounds)) {
                if (powerup.type == Game.powerup.SIZE_UP) {
                    this.greenitemCount++
                    Game.sound.playSound(Game.sound.GREEN_ITEM)
                    this.mainPaddle.incSize()
                    powerup.dead = true
                } else if (powerup.type == Game.powerup.SIZE_DOWN) {
                    this.reditemCount++
                    Game.sound.playSound(Game.sound.RED_ITEM)
                    this.mainPaddle.decSize()
                    powerup.dead = true
                } else if (powerup.type == Game.powerup.POWER_UP) {
                    this.isSuper = true
                    this.yellowitemCount++
                    Game.sound.playSound(Game.sound.SUPER_BALL)
                    for (var j = 0; j < this.balls.length; j++) {
                        if (!this.balls[j].supermode) {
                            this.balls[j].supermode = true
                            this.balls[j].changeSpeed(Ball.SUPER_SPEED_INC)
                        }
                    }
                    this.startTime = new Date().getTime() //start a new time every time you get the orange powerup
                    this.startWatch = true
                    this.bgChange = Game.SUPER_BGCHANGE_SPEED // increase bg change to give a fast gaming effect
                    powerup.dead = true
                } else if (powerup.type == Game.powerup.BACKUP_PADDLE) {
                    this.blueitemCount++
                    Game.sound.playSound(Game.sound.WHITE_ITEM)
                    this.backupPaddle = true
                    powerup.dead = true
                } else if (powerup.type == Game.powerup.DEATH_BOMB) {
                    this.bgChange = Game.NORMAL_BGCHANGE_SPEED // go back to original change speed
                    this.startWatch = false
                    Game.sound.playSound(Game.sound.BURST)

                    powerup.explode = true
                    this.transitions.startBlackBombAnimation(powerup)
                } else if (powerup.type == Game.powerup.MAGIC_COVER) {
                    this.whiteitemCount++
                    Game.sound.playSound(Game.sound.WHITE_ITEM)
                    // can only get 10 of them at most
                    if (this.magiccover < 10) {
                        this.magiccover++
                    }
                    powerup.dead = true
                }
            }
        }

        // count how much time is left for super ball mode
        if (this.startWatch) {
            var nowMs = new Date().getTime()
            this.timePassed = Math.floor((nowMs - this.startTime) / 1000)
            if (this.timePassed > 10) {
                this.isSuper = false
                this.bgChange = Game.NORMAL_BGCHANGE_SPEED // go back to original change speed
                this.startWatch = false
                for (var i = 0; i < this.balls.length; i++) {
                    this.balls[i].supermode = false
                    this.balls[i].changeSpeed(-Ball.SUPER_SPEED_INC)
                }
            }
        }

        for (i = 0; i < this.balls.length; i++) {
            var paddleLine = this.mainPaddle.paddleLine
            this.balls[i].update(deltaMs)
        }

        if (this.ballCount == 0) {
            this.bgChange = Game.NORMAL_BGCHANGE_SPEED; // go back to original change speed
            this.startWatch = false
            this.gameOver = true
        } else if (this.brickCount == 0) {
            // No more bricks, goto next level.
            this.levelComplete()
        }

        this.mainPaddle.update()

        // set bounds for magiccovers
        this.magiccoverBounds.x1 = this.mainPaddle.bounds.x1 - 20;
        this.magiccoverBounds.y1 = this.mainPaddle.bounds.y1 - 20;
        this.magiccoverBounds.x2 = this.mainPaddle.bounds.x2 + 20;
        this.magiccoverBounds.y2 = this.mainPaddle.bounds.y2 + 20;
    }

    render(g) {
        var i, j;

        // determine background color
        if (this.gameState == Game.GAME) {
            if (!this.gameOver) {
                this.hsvColor[0] = this.count * 360;
                this.hsvColor[1] = this.count;
                this.hsvColor[2] = this.count;

                var color = cs.graphics.hsvToRgb(this.hsvColor[0], this.hsvColor[1], this.hsvColor[2])
                g.fillColor(color)
            } else {
                g.fillColor(Color.black)
            }
        } else if (this.gameState == Game.MAINMENU) {
            g.fillColor(Color.black)
        } else if (this.gameState == Game.COLLECTION) {
            g.fillColor(Color.black)
        } else {
            g.fillColor(Color.black)
        }

        g.rect(0, 0, this.width, this.height);

        this.renderButtons(g);

        g.fontSize(this.normalFont)
        g.fillColor(Color.white)
        //c.drawText("FPS: " + fps, 10, PHEIGHT - 60, p);

        if (this.gameState == Game.COLLECTION) {
            g.fillColor(Color.darkGray)
            g.rect(0, 10, Game.PWIDTH, 100)

            g.fontSize(this.titleFont)
            g.textAlign(TextAlign.right)
            g.fillColor(Color.lime)
            g.text(Game.PWIDTH - 20, 78, this.getCompletionPercentage() + '%')
            g.textAlign(TextAlign.left)
            g.fillColor(Color.skyBlue)
            g.text(20, 78, 'Collection')

            g.fontSize(this.subsubtitleFont)
            for (i = 1; i < this.totalLevels + 1; i++) {
                if (this.collection[i - 1]) {
                    g.fillColor(Color.white)
                } else {
                    g.fillColor(Color.red)
                }
                g.text(50, 110 + i * 40, "Stage " + i)
            }

            g.strokeColor(Color.yellow)
            g.rectOutline(this.collectionSelectX, this.collectionSelectY + this.collectionSelectHeight * this.collectionSelect,
                this.collectionSelectWidth, this.collectionSelectHeight)

            var top = 150
            var rightX = Game.PWIDTH / 2 - 40

            var rightRightX = rightX + 170

            g.fontSize(this.subsubtitleFont)
            g.fillColor(Color.white)
            g.text(rightX, top, 'Difficulty.')
            if (this.collectionSelect + 1 <= 5) {
                g.fillColor(Color.lime)
                g.text(rightRightX, top, 'Easy')
            }
            if (this.collectionSelect + 1 > 5 && this.collectionSelect + 1 <= 10) {
                g.fillColor(Color.yellow)
                g.text(rightRightX, top, 'Medium')
            }
            if (this.collectionSelect + 1 > 10 && this.collectionSelect + 1 <= 15) {
                g.fillColor(Color.red)
                g.text(rightRightX, top, 'Hard')
            }

            this.drawMiniStage(g, rightX, Game.MINI_STAGE_Y)

            if (this.collection[this.collectionSelect]) {
                g.fontSize(this.subtitleFont)
                this.collectionPlayButton.render(g)
            }

            g.fontSize(this.subsubtitleFont)
            g.fillColor(Color.white)
            g.text(rightX, top + 40, "High Score.")
            if (this.collectionScores[this.collectionSelect] == 0) {
                g.fillColor(Color.red)
                g.text(rightRightX, top + 40, "None")
            }
            if (this.collectionScores[this.collectionSelect] > 0) {
                g.fillColor(Color.lime)
                g.text(rightRightX, top + 40, this.collectionScores[this.collectionSelect]);
            }
        } else if (this.gameState == Game.MAINMENU) {
            g.fillColor(Color.royalBlue)
            g.rect(0, 80, Game.PWIDTH, 100)

            g.fontSize(this.titleFont)
            g.fillColor(Color.white)
            g.textAlign(TextAlign.center);
            g.text(Game.PWIDTH / 2, 150, 'Paddle Ball')
            g.textAlign(TextAlign.left);
        } else if (this.gameState == Game.PRETEXT) {
            if (this.preText && this.preText !== '') {
                g.fillColor(Color.black)
                g.rect(0, 0, Game.PWIDTH, Game.PHEIGHT)
                g.fillColor(Color.skyBlue)
                g.fontSize(this.titleFont)
                g.textAlign(TextAlign.center)
                g.text(Game.PWIDTH / 2, Game.PHEIGHT / 2, this.preText)
                g.textAlign(TextAlign.left)
            }
        } else if (this.gameState == Game.GAME) {
            if (!this.gameOver) {
                for (i = 0; i < this.bricks.length; i++) {
                    for (j = 0; j < this.bricks[0].length; j++) {
                        if (this.bricks[i][j]) {
                            this.bricks[i][j].render(g);
                        }
                    }
                }
                for (i = 0; i < this.balls.length; i++) {
                    this.balls[i].render(g);
                }

                if (this.backupPaddle) {
                    g.fillColor(Color.blue)
                    g.rect(0, Game.BACKUP_PADDLE_Y, Game.PWIDTH, 20)
                }

                this.mainPaddle.render(g)

                for (i = 0; i < this.powerups.length; i++) {
                    if (this.powerups[i]) {
                        this.powerups[i].render(g)
                    }
                }

                // draw magic cover
                if (this.magiccover > 0) {
                    g.strokeColor(Color.white)
                    var ovalBounds = {}
                    for (i = 0; i < this.magiccover; i++) {
                        ovalBounds.x1 = this.mainPaddle.bounds.x1 - 20 - i
                        ovalBounds.y1 = this.mainPaddle.bounds.y1 - 20 - i
                        ovalBounds.x2 = this.mainPaddle.bounds.x2 + 20 + i
                        ovalBounds.y2 = this.mainPaddle.bounds.y2 + 20 + i
                        g.rectOutline(ovalBounds.x1, ovalBounds.y1, ovalBounds.x2 - ovalBounds.x1, ovalBounds.y2 - ovalBounds.y1)
                    }
                }

                g.fillColor(Color.black)
                g.rect(0, Game.ROOM_BOTTOM_Y, Game.PWIDTH, Game.PHEIGHT)

                g.fillColor(Color.white)
                g.fontSize(this.subtitleFont)
                g.textAlign(TextAlign.right)
                g.text(Game.PWIDTH - 20, Game.PHEIGHT - 50, "Level " + this.level)
                g.textAlign(TextAlign.left)
                g.text(20, Game.PHEIGHT - 50, "Score. " + this.score)
                if (this.startWatch) {
                    g.fontSize(this.subtitleFont)
                    g.textAlign(TextAlign.center)
                    g.fillColor(Color.yellow)
                    g.text(Game.PWIDTH / 2, Game.ROOM_BOTTOM_Y - 15, "SUPER " + (10 - this.timePassed))
                    g.textAlign(TextAlign.left)
                }
            } else {
                if (!this.showScore) {
                    g.fillColor(Color.skyBlue)
                    g.textAlign(TextAlign.center)
                    g.fontSize(this.titleFont)
                    g.text(Game.PWIDTH / 2, Game.PHEIGHT / 3, "Game Over");
                    g.textAlign(TextAlign.left);

                    g.fontSize(this.subtitleFont)
                    this.tryAgainButton.render(g)
                    this.gameOverMenuButton.render(g)
                } else {
                    g.fillColor(Color.lime)
                    g.fontSize(this.titleFont)
                    g.text(20, 80, "Stage " + this.level + ". Cleared!")
                    g.fontSize(this.subtitleFont)
                    g.fillColor(Color.gray)
                    g.text(20, 150, "Level Score. ")
                    if (this.whichScore == 1 && !this.transitions.hasNext) {
                        if (this.scoreCount > this.score) {
                            this.scoreCount = this.score;
                            this.transitions.setNext(this.transitions.startShowGreenScore.bind(this.transitions), 200);
                        } else {
                            this.scoreCount += 5;
                        }
                    }

                    if (this.whichScore >= 2) {
                        g.fillColor(Color.white)
                        g.text(20, 210, 'Paddle Extentions. ' + this.greenitemScoreCount);
                        if (this.whichScore == 2 && !this.transitions.hasNext) {
                            if (this.greenitemScoreCount > this.greenitemCount * 15) {
                                this.greenitemScoreCount = this.greenitemCount * 15;
                                this.transitions.setNext(this.transitions.startShowRedScore.bind(this.transitions), 200);
                            } else {
                                this.greenitemScoreCount += 5;
                            }
                        }
                    }
                    if (this.whichScore >= 3) {
                        g.fillColor(Color.white)
                        g.text(20, 270, "Paddle Shortage. " + this.reditemScoreCount)
                        if (this.whichScore == 3 && !this.transitions.hasNext) {
                            if (this.reditemScoreCount > this.reditemCount * 15) {
                                this.reditemScoreCount = this.reditemCount * 15;
                                this.transitions.setNext(this.transitions.startShowBlueScore.bind(this.transitions), 200);
                            } else {
                                this.reditemScoreCount += 5;
                            }
                        }
                    }
                    if (this.whichScore >= 4) {
                        g.fillColor(Color.white)
                        g.text(20, 330, "Paddle Backup. " + this.blueitemScoreCount)
                        if (this.whichScore == 4 && !this.transitions.hasNext) {
                            if (this.blueitemScoreCount > this.blueitemCount * 30) {
                                this.blueitemScoreCount = this.blueitemCount * 30;
                                this.transitions.setNext(this.transitions.startShowWhiteScore.bind(this.transitions), 200);
                            } else {
                                this.blueitemScoreCount += 5;
                            }
                        }
                    }
                    if (this.whichScore >= 5) {
                        g.fillColor(Color.white)
                        g.text(20, 390, "Paddle Shields. " + this.whiteitemScoreCount)
                        if (this.whichScore == 5 && !this.transitions.hasNext) {
                            if (this.whiteitemScoreCount > this.whiteitemCount * 35) {
                                this.whiteitemScoreCount = this.whiteitemCount * 35;
                                this.transitions.setNext(this.transitions.startShowYellowScore.bind(this.transitions), 200);
                            } else {
                                this.whiteitemScoreCount += 5;
                            }
                        }
                    }
                    if (this.whichScore >= 6) {
                        g.fillColor(Color.white)
                        g.text(20, 450, "Power Balls. " + this.yellowitemScoreCount)
                        if (this.whichScore == 6 && !this.transitions.hasNext) {
                            if (this.yellowitemScoreCount > this.yellowitemCount * 60) {
                                this.yellowitemScoreCount = this.yellowitemCount * 60;
                                this.transitions.setNext(this.transitions.startShowTotalScore.bind(this.transitions), 200);
                            } else {
                                this.yellowitemScoreCount += 5;
                            }
                        }
                    }
                    if (this.whichScore >= 7) {
                        if (this.whichScore == 7 && !this.transitions.hasNext) {
                            if (this.totalScoreCount > this.totalScore) {
                                this.totalScoreCount = this.totalScore;
                                this.transitions.setNext(this.transitions.scoreEnd.bind(this.transitions), 200);
                            } else {
                                this.totalScoreCount += 10;
                            }
                        }
                        g.fillColor(Color.lime)
                        g.text(20, 510, "Total Score. " + this.totalScoreCount)
                    }
                    if (this.whichScore >= 8) {
                        g.fontSize(this.subtitleFont)
                        if (this.level < Game.resources.getTotalLevels()) {
                            this.nextButton.render(g);
                        }
                        this.menuButton.render(g);
                    }
                }
            }
        }
    }
    
    loadLevel(level) {
        this.isSuper = false;
        this.showScore = false; // dont show score
        this.whichScore = 0; // which score to show first (0 - level score)
        this.score = 0; // reset level score
        this.totalScore = 0; // total score

        // counts used when showing scores
        this.totalScoreCount = 0;
        this.greenitemCount = 0;
        this.reditemCount = 0;
        this.blueitemCount = 0;
        this.whiteitemCount = 0;
        this.yellowitemCount = 0;
        this.greenitemScoreCount = 0;
        this.reditemScoreCount = 0;
        this.blueitemScoreCount = 0;
        this.whiteitemScoreCount = 0;
        this.yellowitemScoreCount = 0;
        this.scoreCount = 0;

        this.backupPaddle = false; // default, no backup paddle
        this.magiccover = 0; // default, no magic covers
        this.magiccoverBounds = {};

        //Game.sound.stopMusic();

        this.gameState = Game.PRETEXT;
        this.gameOver = false;
        this.powerupCount = 0; // start in the beginning of indice
        // check how many objects to create
        var bricksPerLine = 1;

        const data = cs.files.readText(`${root}/assets/paddleball/${level}.txt`);
        if (data == null) {
            panic(errString(data))
        }
        var lines = data.split("\n");
        bricksPerLine = parseInt(lines.shift());

        Game.BRICKS_WIDTH = Game.PWIDTH / bricksPerLine;

        var ch;
        var brickCount = 0;
        let targetBrickCount = 0
        var ballCount = 0;

        var brickRows = 0;
        var row = 0;

        var line;
        var i;
        while ((line = lines.shift()) !== undefined) {
            row++;
            for (i = 0; i < line.length; i++) {
                ch = line.charAt(i);
                if (ch == 'B' || ch == 'M') {
                    brickRows = row;
                    brickCount++;
                    if (ch == 'B') {
                        targetBrickCount += 1
                    }
                }
                if (ch == 'O') {
                    ballCount++;
                }
            }
        }
        this.brickCount = targetBrickCount
        this.ballCount = ballCount
        this.bricks = [];
        for (i = 0; i < brickRows; i++) {
            row = [];
            for (var j = 0; j < bricksPerLine; j++) {
                row.push(false);
            }
            this.bricks.push(row);
        }
        this.powerups = []; // there should be as many ups as there are bricks
        this.balls = [];

        // create the objects
        var lineCount = 0;
        lines = data.split("\n").splice(1);
        brickCount = 0; // this time used for the indice of the brick array
        ballCount = 0; // this time used for the indice of the ball array
        row = 0;
        while ((line = lines.shift()) !== undefined) {
            row++;
            for (i = 0; i < line.length; i++) {
                ch = line.charAt(i);
                if (ch == 'B') {
                    this.bricks[row - 1][i] = createBrick(i * Game.BRICKS_WIDTH, lineCount * Game.BRICKS_HEIGHT,
                        Game.BRICKS_WIDTH, Game.BRICKS_HEIGHT);
                    brickCount++;
                }
                if (ch == 'M') {
                    this.bricks[row - 1][i] = createBrick(i * Game.BRICKS_WIDTH, lineCount * Game.BRICKS_HEIGHT,
                        Game.BRICKS_WIDTH, Game.BRICKS_HEIGHT);
                    this.bricks[row - 1][i].metal = true;
                    brickCount++;
                }
                if (ch == 'O') {
                    this.balls[ballCount] = createBall(i * Game.BRICKS_WIDTH + (Game.BRICKS_WIDTH / 2),
                        lineCount * Game.BRICKS_HEIGHT + (Game.BRICKS_HEIGHT / 2), 0.4);
                    // this.balls[ballCount] = createBall(i * Game.BRICKS_WIDTH + (Game.BRICKS_WIDTH / 2),
                    //     lineCount * Game.BRICKS_HEIGHT + (Game.BRICKS_HEIGHT / 2), 0.1);
                    ballCount++;
                }
            }
            lineCount++;
        }

        this.mainPaddle = new Game.paddle(Game.PWIDTH / 10, Game.BACKUP_PADDLE_Y - 60, 80, 10)

        this.level = level;

        this.transitions.startShowStage(level);
    }

    drawMiniStage(g, x, y) {
        var scale = 2
        var MINI_PWIDTH = Game.PWIDTH / scale
        var MINI_PHEIGHT = Game.PHEIGHT / scale
        var MINI_BRICKS_HEIGHT = Game.PHEIGHT / 30 / scale
        var MINI_BALL_SIZE = MINI_BRICKS_HEIGHT //ball size
        var bricksPerLine = 0
        var MINI_BRICKS_WIDTH = 0
        if (this.collection[this.collectionSelect]) {
            const data = cs.files.readText(`${root}/assets/paddleball/${this.collectionSelect + 1}.txt`);
            if (data == null) {
                panic(errString(data))
            }
            var lines = data.split("\n");
            bricksPerLine = parseInt(lines.shift());
            MINI_BRICKS_WIDTH = Game.PWIDTH / 11 / scale;
            var lineCount = 0;
            var ch;
            var line;
            while ((line = lines.shift()) !== undefined) {
                for (var i = 0; i < line.length; i++) {
                    ch = line.charAt(i);
                    if (ch == 'B') {
                        g.fillColor(Color.royalBlue)
                        g.rect(
                            x + i * MINI_BRICKS_WIDTH,
                            y + lineCount * MINI_BRICKS_HEIGHT,
                            MINI_BRICKS_WIDTH, MINI_BRICKS_HEIGHT);
                    }
                    if (ch == 'M') {
                        g.fillColor(Color.lightGray)
                        g.rect(
                            x + i * MINI_BRICKS_WIDTH,
                            y + lineCount * MINI_BRICKS_HEIGHT,
                            MINI_BRICKS_WIDTH, MINI_BRICKS_HEIGHT);
                    }
                    if (ch == 'O') {
                        g.fillColor(Color.white)
                        g.circleSector(
                            x + i * MINI_BRICKS_WIDTH + (MINI_BRICKS_WIDTH / 2),
                            y + lineCount * MINI_BRICKS_HEIGHT + (MINI_BRICKS_HEIGHT / 2),
                            MINI_BALL_SIZE / 2, 0, 2 * Math.PI);
                    }
                }
                lineCount++;
            }
        } else {
            bricksPerLine = 11
            MINI_BRICKS_WIDTH = Game.PWIDTH / bricksPerLine / scale
        }
        if (!this.collection[this.collectionSelect]) {
            g.fillColor(Color.red)
            g.fontSize(this.subtitleFont)
            g.textAlign(TextAlign.center)
            g.text(x + (MINI_BRICKS_WIDTH * bricksPerLine) / 2, y + MINI_PHEIGHT / 2, "LOCKED")
            g.textAlign(TextAlign.left)
        }
        g.strokeColor(Color.white)
        g.rectOutline(x, y, MINI_BRICKS_WIDTH * bricksPerLine, MINI_PHEIGHT)
    }

    getCompletionPercentage() {
        var highestLevel = 0;
        for (var i = 0; i < this.totalLevels; i++) {
            if (this.collectionScores[i] > 0) {
                highestLevel = i + 1;
            }
        }
        return Math.floor((highestLevel / this.totalLevels) * 100);
    }

    levelComplete() {
        if (!this.inTransition) {
            this.transitions.startLevelComplete();
        }
    }

    displayLastLevelMessage() {
        navigator.notification.alert(
            'You beat the last level! Stay tuned for more levels and gameplay.',
            function() {},
            '',
            'OK'
        );
    }

    updateBgColor(deltaMs) {
        if (this.countUp) {
            this.count = this.count + this.bgChange * deltaMs;
        } else {
            this.count = this.count - this.bgChange * deltaMs;
        }
        if (this.count > 1) {
            this.countUp = false;
        } else if (this.count < 0.25) {
            this.countUp = true;
        }
    }

    renderButtons(g) {
        if (this.gameState == Game.MAINMENU) {
            g.fontSize(this.subtitleFont)
            this.playButton.render(g);
            this.collectionButton.render(g);

            g.fillColor(Color.skyBlue)
            g.textAlign(TextAlign.center);
            g.text(Game.PWIDTH / 2, 392, 'Collection');
            g.fillColor(Color.lime)
            g.text(Game.PWIDTH / 2, 437, this.getCompletionPercentage() + "%");
            g.textAlign(TextAlign.left);

            this.soundButton.render(g);
            g.fillColor(Color.skyBlue)
            g.textAlign(TextAlign.center)
            g.text(Game.PWIDTH / 2, 552, "Sound")
            if (this.hasSound) {
                g.fillColor(Color.lime)
                g.text(Game.PWIDTH / 2, 597, "On")
            } else {
                g.fillColor(Color.red)
                g.text(Game.PWIDTH / 2, 597, "Off")
            }
            g.textAlign(TextAlign.left)
        }
    }

    hitBrick(row, col) {
        // create a random powerup
        var randomSpeed = Math.random() * 0.1 + 0.13;

        var brickBounds = this.bricks[row][col].bounds;
        this.powerups[this.powerupCount] = createPowerup((brickBounds.x1 + brickBounds.x2) / 2, (brickBounds.y1 + brickBounds.y2) / 2, randomSpeed);
        this.powerupCount++; // increase the indice

        Game.sound.playSound(Game.sound.BRICK_HIT);
        this.score = this.score + 10;
        this.bricks[row][col] = false
        this.brickCount -= 1
    }

    onHandTouchEnd(e) {
        var touches = e.originalEvent.changedTouches;
        var touchX = touches[0].pageX;
        var touchY = touches[0].pageY;
        this.onTouchEnd(touchX, touchY);
    }

    onMouseClick(x, y) {
        this.onTouchEnd(x, y);
    }

    onTouchEnd(touchX, touchY) {
        if (this.gameState == Game.MAINMENU) {
            if (this.playButton.contains(touchX, touchY)) {
                Game.sound.playSound(Game.sound.MENU_SELECT);
                this.start();
            } else if (this.collectionButton.contains(touchX, touchY)) {
                Game.sound.playSound(Game.sound.MENU_SELECT);
                this.findLevels();
                this.gameState = Game.COLLECTION;
            } else if (this.soundButton.contains(touchX, touchY)) {
                this.hasSound = !this.hasSound;
                if (this.hasSound) {
                    Game.sound.enable();
                } else {
                    Game.sound.disable();
                }
                Game.sound.playSound(Game.sound.MENU_SELECT);
                Game.persistence.saveSettings(this.hasSound);
            }
        } else if (this.gameState == Game.GAME) {
            if (this.gameOver) {
                if (this.showScore) {
                    if (this.whichScore == 8) {
                        if (this.menuButton.contains(touchX, touchY)) {
                            Game.sound.stopSound(Game.sound.STAGE_WIN);
                            Game.sound.playSound(Game.sound.MENU_SELECT);
                            //SoundManager.loopMusic(R.raw.menu);
                            this.gameState = Game.MAINMENU;
                        } else if (this.nextButton.contains(touchX, touchY)) {
                            if (this.level < Game.resources.getTotalLevels()) {
                                Game.sound.stopSound(Game.sound.STAGE_WIN);
                                Game.sound.playSound(Game.sound.MENU_SELECT);
                                this.loadLevel(this.level + 1);
                            }
                        }
                    }
                } else {
                    if (this.tryAgainButton.contains(touchX, touchY)) {
                        Game.sound.stopSound(Game.sound.STAGE_WIN);
                        this.loadLevel(this.level);
                    } else if (this.gameOverMenuButton.contains(touchX, touchY)) {
                        Game.sound.playSound(Game.sound.MENU_SELECT);
                        //SoundManager.loopMusic(R.raw.menu);
                        this.gameState = Game.MAINMENU;
                    }
                }
            }
        } else if (this.gameState == Game.COLLECTION) {
            if (touchX >= this.collectionSelectX && touchX <= this.collectionSelectX + this.collectionSelectWidth) {
                for (var i = 0; i < this.totalLevels; i++) {
                    if (touchY >= this.collectionSelectY + i * this.collectionSelectHeight &&
                        touchY < this.collectionSelectY + i * this.collectionSelectHeight + this.collectionSelectHeight) {
                        Game.sound.playSound(Game.sound.MENU_SELECT);
                        this.collectionSelect = i;
                    }
                }
            } else if (this.collectionPlayButton.contains(touchX, touchY)) {
                if (this.collection[this.collectionSelect]) {
                    Game.sound.playSound(Game.sound.MENU_SELECT);
                    this.loadLevel(this.collectionSelect + 1);
                }
            }
        }
    }

    onTouchMove(e) {
        var touches = e.originalEvent.changedTouches;
        var touchX = touches[0].pageX;
        this.onMovePaddle(touchX);
    }

    onMouseMove(x, y) {
        this.onMovePaddle(x);
    }

    onMovePaddle(touchX) {
        if (this.inTransition) {
            return;
        }
        if (this.gameState == Game.GAME) {
            if (!this.gameOver) {
                this.mainPaddle.moveTo(touchX);
            }
        }
    }

    // Will only collide with the closest brick.
    ballBrickCollision(ball) {
        let lowContact = { x: 0, y: 0 }
        let lowSide = false
        let lowBrickRow = 0
        let lowBrickCol = 0
        let lowDist = Number.MAX_VALUE

        var ballLine = ball.pathLine

        var ballStartTileX = Math.floor(ballLine.x1 / Game.BRICKS_WIDTH);
        var ballStartTileY = Math.floor(ballLine.y1 / Game.BRICKS_HEIGHT);
        var ballEndTileX = Math.floor(ballLine.x2 / Game.BRICKS_WIDTH);
        var ballEndTileY = Math.floor(ballLine.y2 / Game.BRICKS_HEIGHT);

        var minTileX, minTileY;
        var maxTileX, maxTileY;

        if (ballStartTileX <= ballEndTileX) {
            minTileX = ballStartTileX - 1;
            maxTileX = ballEndTileX + 1;
        } else {
            minTileX = ballEndTileX - 1;
            maxTileX = ballStartTileX + 1;
        }

        if (ballStartTileY <= ballEndTileY) {
            minTileY = ballStartTileY - 1;
            maxTileY = ballEndTileY + 1;
        } else {
            minTileY = ballEndTileY - 1;
            maxTileY = ballStartTileY + 1;
        }

        minTileX = Math.max(0, minTileX)
        maxTileX = Math.min(this.bricks[0].length-1, maxTileX)
        minTileY = Math.max(0, minTileY)
        maxTileY = Math.min(this.bricks.length-1, Math.max(0, maxTileY))

        // Only check bricks that are around the ball
        for (let row = minTileY; row <= maxTileY; row++) {
            for (let col = minTileX; col <= maxTileX; col++) {
                if (!this.bricks[row][col]) {
                    continue
                }

                var brickBounds = this.bricks[row][col].bounds;
                var brickLeft = brickBounds.x1;
                var brickTop = brickBounds.y1;
                var brickRight = brickBounds.x2;
                var brickBottom = brickBounds.y2;

                if (!circleToAABB(ball.x, ball.y, Ball.SIZE/2, brickBounds.x1, brickBounds.y1, brickBounds.x2, brickBounds.y2)) {
                    continue
                }

                // Check which side.
                let contact = false
                let dist = 0.0

                // Bottom.
                if (ball.lastY > brickBottom) {
                    this.scratchLine = {
                        x1: brickLeft - Ball.SIZE/2, y1: brickBottom + Ball.SIZE/2,
                        x2: brickRight + Ball.SIZE/2, y2: brickBottom + Ball.SIZE/2,
                    }
                    contact = Game.misc.getInfLineIntersect(ballLine, this.scratchLine)
                    if (contact.onLine1) {
                        dist = Game.misc.getPointDistance(ball.lastX, ball.lastY, contact.x, contact.y)
                        if (dist < lowDist) {
                            lowDist = dist
                            lowContact = { x: contact.x, y: contact.y }
                            lowSide = Game.brickside.BOTTOM
                            lowBrickRow = row
                            lowBrickCol = col
                        }
                    }
                }

                // Top.
                if (ball.lastY < brickTop) {
                    this.scratchLine = {
                        x1: brickLeft - Ball.SIZE/2, y1: brickTop - Ball.SIZE/2,
                        x2: brickRight + Ball.SIZE/2, y2: brickTop - Ball.SIZE/2,
                    }
                    contact = Game.misc.getInfLineIntersect(ballLine, this.scratchLine)
                    if (contact.onLine1) {
                        dist = Game.misc.getPointDistance(ball.lastX, ball.lastY, contact.x, contact.y)
                        if (dist < lowDist) {
                            lowDist = dist
                            lowContact = { x: contact.x, y: contact.y }
                            lowSide = Game.brickside.TOP
                            lowBrickRow = row
                            lowBrickCol = col
                        }
                    }
                }

                // Left.
                if (ball.lastX < brickLeft) {
                    this.scratchLine = {
                        x1: brickLeft - Ball.SIZE/2, y1: brickTop - Ball.SIZE/2,
                        x2: brickLeft - Ball.SIZE/2, y2: brickBottom + Ball.SIZE/2,
                    }
                    contact = Game.misc.getInfLineIntersect(ballLine, this.scratchLine)
                    if (contact.onLine1) {
                        dist = Game.misc.getPointDistance(ball.lastX, ball.lastY, contact.x, contact.y)
                        if (dist < lowDist) {
                            lowDist = dist
                            lowContact = { x: contact.x, y: contact.y }
                            lowSide = Game.brickside.LEFT
                            lowBrickRow = row
                            lowBrickCol = col
                        }
                    }
                }

                // Right.
                if (ball.lastX > brickRight) {
                    this.scratchLine = {
                        x1: brickRight + Ball.SIZE/2, y1: brickTop - Ball.SIZE/2,
                        x2: brickRight + Ball.SIZE/2, y2: brickBottom + Ball.SIZE/2,
                    }
                    contact = Game.misc.getInfLineIntersect(ballLine, this.scratchLine)
                    if (contact.onLine1) {
                        dist = Game.misc.getPointDistance(ball.lastX, ball.lastY, contact.x, contact.y)
                        if (dist < lowDist) {
                            lowDist = dist
                            lowContact = { x: contact.x, y: contact.y }
                            lowSide = Game.brickside.RIGHT
                            lowBrickRow = row
                            lowBrickCol = col
                        }
                    }
                }
            }
        }

        if (lowSide !== false) {
            if (this.bricks[lowBrickRow][lowBrickCol].metal || !this.isSuper) {
                if (lowSide == Game.brickside.TOP) {
                    ball.setMotion(lowContact.x, lowContact.y, -ball.dir)
                } else if (lowSide == Game.brickside.BOTTOM) {
                    ball.setMotion(lowContact.x, lowContact.y, -ball.dir)
                } else if (lowSide == Game.brickside.LEFT) {
                    ball.setMotion(lowContact.x, lowContact.y, -ball.dir + Math.PI)
                } else if (lowSide == Game.brickside.RIGHT) {
                    ball.setMotion(lowContact.x, lowContact.y, -ball.dir + Math.PI)
                }
            }

            if (this.bricks[lowBrickRow][lowBrickCol].metal) {
                Game.sound.playSound(Game.sound.METAL_HIT)
            } else {
                this.hitBrick(lowBrickRow, lowBrickCol)
            }

            if (this.isSuper) {
                // Since super mode keeps going,
                // continue to check for bricks since the collision will only choose one brick at a time.
    -           this.ballBrickCollision(ball)
            }
        }
    }
}

class Ball {
    static SHADOW_MAX = 40
    static SIZE = 16
    static PADDLE_SPEED_INC = 0.003
    static SUPER_SPEED_INC = 0.25
    static MIN_PADDLE_BOUNCE_RAD = Math.PI / 8
    static MAX_PADDLE_BOUNCE_RAD = 7 * Math.PI / 8

    constructor() {
        this.supermode = false
        this.x = 0.0; this.y = 0.0; this.lastX = 0.0; this.lastY = 0.0;
        this.speed = 0.0;
        this.width = Ball.SIZE
        this.height = Ball.SIZE

        // In radians.
        this.dir = 0.0

        this.dead = false
        this.bounds = {}
        this.pathLine = {}
    }

    updatePathLine() {
        this.pathLine.x1 = this.lastX
        this.pathLine.y1 = this.lastY
        this.pathLine.x2 = this.x
        this.pathLine.y2 = this.y
    }

    updateBounds() {
        this.bounds.x1 = Math.floor(this.x - this.width / 2)
        this.bounds.y1 = Math.floor(this.y - this.height / 2)
        this.bounds.x2 = Math.floor(this.x + this.width / 2)
        this.bounds.y2 = Math.floor(this.y + this.height / 2)
    }

    setMotion(x, y, dir) {
        this.x = x
        this.y = y
        this.updateBounds()
        this.dir = dir
        this.updatePathLine()
    }

    changeSpeed(change) {
        this.speed = this.speed + change
    }

    update(deltaMs) {
        if (this.dead) {
            return
        }

        const targetDist = deltaMs * this.speed

        // Keep performing collision detection until target distance is reached.
        let dist = 0
        while (dist < targetDist) {
            let nextDist = Ball.SIZE
            if (dist + nextDist > targetDist) {
                nextDist = targetDist - dist + 0.001
            }
            dist += nextDist
            this.lastX = this.x
            this.lastY = this.y
            this.x += Math.cos(this.dir) * nextDist
            this.y -= Math.sin(this.dir) * nextDist

            this.updateBounds()
            this.updatePathLine()

            // Room collision.
            if (this.y < this.height / 2) {
                const contact = Game.misc.getLineIntersect(this.pathLine, { x1: 0, y1: this.height/2, x2: Game.PWIDTH, y2: this.height/2 })
                this.setMotion(contact.x, contact.y, -this.dir)
            }
            if (this.x < this.width / 2) {
                const contact = Game.misc.getLineIntersect(this.pathLine, { x1: this.width/2, y1: 0, x2: this.width/2, y2: Game.PHEIGHT })
                this.setMotion(contact.x, contact.y, -this.dir + Math.PI)
            }
            if (this.x > Game.PWIDTH - this.width / 2) {
                const contact = Game.misc.getLineIntersect(this.pathLine, { x1: Game.PWIDTH - this.width/2, y1: 0, x2: Game.PWIDTH - this.width/2, y2: Game.PHEIGHT })
                this.setMotion(Game.PWIDTH - this.width / 2, this.y, -this.dir + Math.PI)
            }
            if (this.y > Game.ROOM_BOTTOM_Y) {
                game.endBall(this)
                break
            }

            // Paddle collision.
            // Only check up direction since the ball can hit the backup bar.
            let shouldDoPaddleCollision = Math.sin(this.dir) < 0
            if (shouldDoPaddleCollision) {
                const paddleLine = game.mainPaddle.paddleLine
                const paddleLineC = {
                    // Account for corners with height of paddle.
                    x1: paddleLine.x1 - game.mainPaddle.height/2, y1: paddleLine.y1 - Ball.SIZE / 2,
                    x2: paddleLine.x2 + game.mainPaddle.height/2, y2: paddleLine.y2 - Ball.SIZE / 2
                }
                let contact = Game.misc.getLineIntersect(this.pathLine, paddleLineC)
                if (contact) {
                    let contactX = contact.x
                    let paddleWidth = paddleLineC.x2 - paddleLineC.x1
                    let intersectXRatio = (paddleLineC.x2 - contactX) / paddleWidth

                    let newDir = Ball.MIN_PADDLE_BOUNCE_RAD + intersectXRatio * (Ball.MAX_PADDLE_BOUNCE_RAD - Ball.MIN_PADDLE_BOUNCE_RAD)
                    this.setMotion(contactX, contact.y, newDir)
                    Game.sound.playSound(Game.sound.PADDLE_HIT)
                    if (!this.supermode) {
                        this.speed = this.speed + Ball.PADDLE_SPEED_INC
                    }
                    continue
                }
            }

            // Backup paddle collision.
            if (game.backupPaddle) {
                if (this.y >= Game.BACKUP_PADDLE_Y) {
                    this.setMotion(this.x, this.y, -this.dir);
                    Game.sound.playSound(Game.sound.PADDLE_HIT)
                    // backup paddle is one time use only
                    game.backupPaddle = false
                }
            }

            game.ballBrickCollision(this)
        }
    }

    renderBall(g) {
        if (this.supermode) {
            g.fillColor(Color.yellow)
        } else {
            g.fillColor(Color.white)
        }
        g.strokeColor(Color.black)
        g.circleSector(this.x, this.y, Ball.SIZE / 2, 0, 2 * Math.PI)
        g.circleArc(this.x, this.y, Ball.SIZE / 2, 0, 2 * Math.PI)
    };

    render(g) {
        if (!this.dead) {
            this.renderBall(g);
        }
    }
}

Game.sound = {
    STAGE_WIN: false,
    GREEN_ITEM: false,
    RED_ITEM: false,
    SUPER_BALL: false,
    WHITE_ITEM: false,
    BURST: false,
    BRICK_HIT: false,
    PADDLE_HIT: false,
    MENU_SELECT: false,
    METAL_HIT: false,
    disabled: false,
    playSound(sound) {
        if (Game.sound.disabled) {
            return;
        }
        sound.playBg();
    },
    stopSound(sound) {
        sound.stopBg();
    },
    disable() {
        Game.sound.disabled = true;
    },
    enable() {
        Game.sound.disabled = false;
    },
    init(channels) {
        // TODO
    },
    load() {
        Game.sound.STAGE_WIN = cs.audio.loadOggFile(`${root}/assets/paddleball/stagewin.ogg`)
        Game.sound.GREEN_ITEM = cs.audio.loadWavFile(`${root}/assets/paddleball/greenitem.wav`)
        Game.sound.WHITE_ITEM = cs.audio.loadWavFile(`${root}/assets/paddleball/whiteitem.wav`)
        Game.sound.BURST = cs.audio.loadWavFile(`${root}/assets/paddleball/burst.wav`)
        Game.sound.BRICK_HIT = cs.audio.loadWavFile(`${root}/assets/paddleball/brickhit.wav`)
        Game.sound.PADDLE_HIT = cs.audio.loadWavFile(`${root}/assets/paddleball/paddlehit.wav`)
        Game.sound.MENU_SELECT = cs.audio.loadWavFile(`${root}/assets/paddleball/menuselect.wav`)
        Game.sound.METAL_HIT = cs.audio.loadWavFile(`${root}/assets/paddleball/metalhit.wav`)
        Game.sound.RED_ITEM = cs.audio.loadWavFile(`${root}/assets/paddleball/reditem.wav`)
        Game.sound.SUPER_BALL = cs.audio.loadWavFile(`${root}/assets/paddleball/superball.wav`)
    }
}

// TODO: Rename to util.
Game.misc = {
    getInfLineIntersect(line1, line2) {
        return Game.misc.getInfLineIntersect2(line1.x1, line1.y1, line1.x2, line1.y2,
            line2.x1, line2.y1, line2.x2, line2.y2)
    },

    getInfLineIntersect2(line1StartX, line1StartY, line1EndX, line1EndY,
        line2StartX, line2StartY, line2EndX, line2EndY) {
        // if the lines intersect,
        // the result contains the x and y of the intersection (treating the lines as infinite) and
        // booleans for whether line segment 1 or line segment 2 contain the point
        var denominator, a, b, numerator1, numerator2, result = {
            x: null,
            y: null,
            onLine1: false,
            onLine2: false
        };
        denominator = ((line2EndY - line2StartY) * (line1EndX - line1StartX)) - ((line2EndX - line2StartX) * (line1EndY - line1StartY));
        if (denominator == 0) {
            return result;
        }
        a = line1StartY - line2StartY;
        b = line1StartX - line2StartX;
        numerator1 = ((line2EndX - line2StartX) * a) - ((line2EndY - line2StartY) * b);
        numerator2 = ((line1EndX - line1StartX) * a) - ((line1EndY - line1StartY) * b);
        a = numerator1 / denominator;
        b = numerator2 / denominator;

        // if we cast these lines infinitely in both directions, they intersect here:
        result.x = line1StartX + (a * (line1EndX - line1StartX));
        result.y = line1StartY + (a * (line1EndY - line1StartY));

        /*
         // it is worth noting that this should be the same as:
         x = line2StartX + (b * (line2EndX - line2StartX));
         y = line2StartX + (b * (line2EndY - line2StartY));
         */
        // if line1 is a segment and line2 is infinite, they intersect if:
        if (a > 0 && a < 1) {
            result.onLine1 = true;
        }
        // if line2 is a segment and line1 is infinite, they intersect if:
        if (b > 0 && b < 1) {
            result.onLine2 = true;
        }
        // if line1 and line2 are segments, they intersect if both of the above are true
        return result;
    },
    getLineIntersect(line1, line2) {
        var result = Game.misc.getInfLineIntersect(line1, line2)
        if (result.onLine1 && result.onLine2) {
            return result;
        } else {
            return false;
        }
    },
    boundsIntersect(bounds1, bounds2) {
        return !(bounds1.x1 > bounds2.x2 ||
            bounds1.x2 < bounds2.x1 ||
            bounds1.y1 > bounds2.y2 ||
            bounds1.y2 < bounds2.y1);
    },
    getPointDistance(x1, y1, x2, y2) {
        return Math.sqrt(Math.pow(x1 - x2, 2) + Math.pow(y1 - y2, 2));
    }
}

Game.paddle = class {

    constructor(x, y, width, height) {
        this.x = x
        this.y = y
        this.initWidth = width
        this.width = width
        this.height = height
        this.bounds = {}
        this.paddleLine = {}
        this.inc = 0
        this.change = Game.PWIDTH / 80
    }

    update() {
        this.bounds.x1 = this.x;
        this.bounds.y1 = this.y;
        this.bounds.x2 = this.x + this.width;
        this.bounds.y2 = this.y + this.height;
        this.paddleLine.x1 = this.x;
        this.paddleLine.y1 = this.y;
        this.paddleLine.x2 = this.x + this.width;
        this.paddleLine.y2 = this.y;
    }

    incSize() {
        if (this.inc < 10) {
            this.inc++;
            this.x = this.x - this.change;
            this.width = this.width + this.change * 2;
        }
    }

    decSize() {
        if (this.inc > 0) {
            this.inc--;
            this.x = this.x + this.change;
            this.width = this.width - this.change * 2;
        }
    }

    moveTo(centerX) {
        this.x = centerX - this.width / 2;
        if (this.x < 0) {
            this.x = 0;
        }
        if (this.x + this.width > Game.PWIDTH) {
            this.x = Game.PWIDTH - this.width;
        }
    }

    render(g) {
        g.fillColor(Color.green)
        g.rect(this.bounds.x1, this.bounds.y1, this.bounds.x2 - this.bounds.x1, this.bounds.y2 - this.bounds.y1);
        g.fillColor(Color.white)
        g.rect(this.x + (this.width - this.initWidth) / 2, this.y, this.initWidth, this.height);
        g.strokeColor(Color.darkGray)
        g.rectOutline(this.x + (this.width - this.initWidth) / 2, this.y, this.initWidth, this.height);
    }
}

Game.powerup = {
    SIZE_UP: 0,
    SIZE_DOWN: 1,
    POWER_UP: 2,
    BACKUP_PADDLE: 3,
    DEATH_BOMB: 4,
    MAGIC_COVER: 5,

    dead: false,
    width: 0, height: 0,
    type: false,
    x: 0.0, y: 0.0,
    speed: 0.0,
    bounds: false,
    explode: false,

    updateBounds() {
        this.bounds.x1 = Math.floor(this.x);
        this.bounds.y1 = Math.floor(this.y);
        this.bounds.x2 = Math.floor(this.x) + this.width;
        this.bounds.y2 = Math.floor(this.y) + this.height;
    },

    increaseSize() {
        var amount = 3;
        this.x = this.x - amount;
        this.y = this.y - amount;
        this.width = this.width + amount * 2;
        this.height = this.height + amount * 2;
        this.updateBounds();
    },

    update(deltaMs) {
        if (!this.dead) {
            this.y = this.y + this.speed * deltaMs;
            this.updateBounds();
            if (this.bounds.y2 > Game.PHEIGHT) {
                this.dead = true;
            }
        }
    },

    render(g) {
        if (!this.dead) {
            if (this.type == Game.powerup.SIZE_UP) {
                g.fillColor(Color.green)
            } else if (this.type == Game.powerup.SIZE_DOWN) {
                g.fillColor(Color.red)
            } else if (this.type == Game.powerup.POWER_UP) {
                g.fillColor(Color.yellow)
            } else if (this.type == Game.powerup.BACKUP_PADDLE) {
                g.fillColor(Color.blue)
            } else if (this.type == Game.powerup.DEATH_BOMB) {
                g.fillColor(Color.black)
            } else if (this.type == Game.powerup.MAGIC_COVER) {
                g.fillColor(Color.white)
            }
            if (this.explode) {
                g.circle(this.x + this.width / 2, this.y + this.height / 2, this.width / 2)
            } else {
                g.rect(this.x, this.y, this.width, this.height);
            }

            g.strokeColor(Color.black)
            if (this.explode) {
                g.circleOutline(this.x + this.width / 2, this.y + this.height / 2, this.width / 2)
            } else {
                g.rectOutline(this.x, this.y, this.width, this.height);
            }
        }
    }
}

Game.brickside = {
    TOP: 0,
    LEFT: 1,
    RIGHT: 2,
    BOTTOM: 3
}

Game.brick = {
    x: 0, y: 0, width: 0, height: 0,
    bounds: false,
    metal: false,

    render(g) {
        if (this.metal) {
            g.fillColor(Color.lightGray)
            g.rect(this.x, this.y, this.width, this.height)
            g.strokeColor(Color.darkGray)
            g.rectOutline(this.x, this.y, this.width, this.height)
        } else {
            g.fillColor(Color.royalBlue)
            g.rect(this.x, this.y, this.width, this.height)
            g.strokeColor(Color.darkBlue)
            g.rectOutline(this.x, this.y, this.width, this.height)
        }
    }
}

Game.button = {
    bounds: false,
    text: '',
    bgColor: Color.black, fgColor: 0, borderColor: 0,

    contains(x, y) {
        return x >= this.bounds.x1 && x <= this.bounds.x2 &&
            y >= this.bounds.y1 && y <= this.bounds.y2;
    },
    render(g) {
        g.fillColor(this.bgColor)
        g.rect(this.bounds.x1, this.bounds.y1, this.bounds.x2 - this.bounds.x1, this.bounds.y2 - this.bounds.y1);
        g.strokeColor(this.borderColor)
        g.rectOutline(this.bounds.x1, this.bounds.y1, this.bounds.x2 - this.bounds.x1, this.bounds.y2 - this.bounds.y1);

        g.fillColor(this.fgColor)
        g.textAlign(TextAlign.center);
        g.textBaseline(TextBaseline.middle)
        g.text((this.bounds.x1 + this.bounds.x2) / 2, (this.bounds.y1 + this.bounds.y2) / 2, this.text)
        g.textBaseline(TextBaseline.alphabetic)
        g.textAlign(TextAlign.left);
    }
}

Game.resources = {
    getTotalLevels() {
        return 15;
    }
}

Game.persistence = {
    HIGHSCORES_KEY: 'highscores',
    SOUND_KEY: 'sound',

    getValueOrDefault(key, def) {
        const data = cs.files.readText(getAppDir(AppName) + `/${key}.txt`)
        if (data != null) {
            return data
        } else {
            return def
        }
    },

    getSound() {
        return this.getValueOrDefault(Game.persistence.SOUND_KEY, true);
    },

    saveSettings(sound) {
        const path = getAppDir(AppName) + '/sound.txt' 
        if (!cs.files.writeText(path, JSON.stringify(sound))) {
            panic('Write failed.')
        }
    },

    getHighscores() {
        var i;
        var highscoresJson = this.getValueOrDefault(Game.persistence.HIGHSCORES_KEY, '');

        var highscores = [];
        for (i = 0; i < Game.resources.getTotalLevels(); i++) {
            highscores[i] = 0;
        }

        if (highscoresJson) {
            var savedHighscores = JSON.parse(highscoresJson);
            for (i = 0; i < savedHighscores.length; i++) {
                if (i == highscores.length) {
                    break;
                }
                highscores[i] = parseInt(savedHighscores[i]);
            }
        }

        return highscores;
    },

    saveHighscores(highscores) {
        const path = getAppDir(AppName) + '/highscores.txt' 
        if (!cs.files.writeText(path, JSON.stringify(highscores))) {
            panic('Write failed.')
        }
    }
}

function createButton(text, left, top, width, height) {
    var button = Object.create(Game.button);
    button.bounds = {};
    button.bounds.x1 = left;
    button.bounds.y1 = top;
    button.bounds.x2 = left + width;
    button.bounds.y2 = top + height;
    button.text = text;
    button.textBounds = {};
    button.bgColor = Color.darkGray
    button.fgColor = Color.skyBlue
    button.borderColor = Color.lightGray
    return button;
}

function createBrick(x, y, width, height) {
    var brick = Object.create(Game.brick)
    brick.x = x
    brick.y = y
    brick.width = width
    brick.height = height
    brick.bounds = {}
    brick.bounds.x1 = x
    brick.bounds.y1 = y
    brick.bounds.x2 = x + width
    brick.bounds.y2 = y + height
    return brick
}

function createPowerup(x, y, speed) {
    var powerup = Object.create(Game.powerup);
    powerup.x = x;
    powerup.y = y;
    powerup.width = Game.PWIDTH / 30;
    powerup.height = powerup.width;
    powerup.speed = speed;
    powerup.bounds = {};
    powerup.bounds.x1 = x;
    powerup.bounds.y1 = y;
    powerup.bounds.x2 = x + powerup.width;
    powerup.bounds.y2 = y + powerup.height;

    var random = Math.floor(Math.random() * 20);
    if (random >= 0 && random < 5) {
        powerup.type = Game.powerup.SIZE_UP;
    } else if (random >= 5 && random < 10) {
        powerup.type = Game.powerup.SIZE_DOWN;
    } else if (random >= 10 && random < 12) {
        powerup.type = Game.powerup.POWER_UP;
    } else if (random >= 12 && random < 14) {
        powerup.type = Game.powerup.BACKUP_PADDLE;
    } else if (random >= 14 && random < 17) {
        powerup.type = Game.powerup.DEATH_BOMB;
    } else if (random >= 17 && random < 20) {
        powerup.type = Game.powerup.MAGIC_COVER;
    }
    powerup.dead = false;
    return powerup;
}

function createBall(x, y, speed) {
    var ball = new Ball()
    ball.speed = speed;
    var random = Math.floor(Math.random() * 4);
    var dir = 0;
    if (random == 0) {
        dir = Math.PI / 4;
    } else if (random == 1) {
        dir = 3 * Math.PI / 4;
    } else if (random == 2) {
        dir = 5 * Math.PI / 4;
    } else if (random == 3) {
        dir = 7 * Math.PI / 4;
    }

    ball.setMotion(x, y, dir);

    ball.dead = false;
    return ball;
}

class Transitions {

    constructor(game) {
        this.hasNext = false
        this.game = game
    }

    setNext(callback, timeoutMs) {
        this.hasNext = true
        setTimeout(timeoutMs, function() {
            this.hasNext = false
            callback()
        }.bind(this))
    }

    startBlackBombAnimation(powerup) {
        this.game.inTransition = true
        for (var j = 0; j < 30; j++) {
            setTimeout(j * 50, this.blackBombTick.bind(this), powerup);
        }
        setTimeout(30 * 50, this.endBlackBomb.bind(this));
    }

    blackBombTick(powerup) {
        powerup.increaseSize()
    }

    endBlackBomb() {
        this.game.inTransition = false
        this.game.gameOver = true
    }

    startShowStage(level) {
        this.game.inTransition = true
        this.game.preText = 'Stage ' + level;
        setTimeout(800, this.triggerGetReady.bind(this))
        setTimeout(1600, this.triggerGo.bind(this))
        setTimeout(2400, this.triggerStartLevel.bind(this))
    }

    triggerGetReady() {
        this.game.preText = 'Get Ready!'
    }

    triggerGo() {
        this.game.preText = 'Go!'
    }

    triggerStartLevel() {
        this.game.restartLastTime()
        this.game.preText = ''
        this.game.gameState = Game.GAME
        this.game.inTransition = false
    }

    startLevelComplete() {
        this.game.inTransition = true
        this.game.bgChange = Game.NORMAL_BGCHANGE_SPEED // go back to original change speed
        this.game.startWatch = false

        //Game.sound.stopMusic();

        setTimeout(500, this.startShowResultsAndStageCleared.bind(this))
    }

    startShowResultsAndStageCleared() {
        // show score results
        // show stage cleared
        this.game.stageWinStreamId = Game.sound.playSound(Game.sound.STAGE_WIN)
        this.game.gameOver = true
        this.game.showScore = true
        setTimeout(1000, this.startShowLevelScore.bind(this))
    }

    startShowLevelScore() {
        // show level score
        this.game.whichScore++
        this.game.scoreCount = 0
    }

    startShowGreenScore() {
        this.game.whichScore++
        this.game.greenitemScoreCount = 0
    }

    startShowRedScore() {
        this.game.whichScore++
        this.game.reditemScoreCount = 0
    }

    startShowBlueScore() {
        this.game.whichScore++
        this.game.blueitemScoreCount = 0
    }

    startShowWhiteScore() {
        this.game.whichScore++
        this.game.whiteitemScoreCount = 0
    }

    startShowYellowScore() {
        this.game.whichScore++
        this.game.yellowitemScoreCount = 0
    }

    startShowTotalScore() {
        this.game.whichScore++
        this.game.totalScore = this.game.score + this.game.greenitemCount * 15 + this.game.blueitemCount * 30
            + this.game.whiteitemCount * 35 + this.game.yellowitemCount * 60 - this.game.reditemCount * 15;
        this.game.totalScoreCount = 0
    }

    scoreEnd() {
        if (this.game.level < Game.resources.getTotalLevels()) {
            // unlock next level
            this.game.collection[this.game.level] = true;
        } else {
            this.game.displayLastLevelMessage();
        }

        // if its a better score save it
        if (this.game.totalScore > this.game.collectionScores[this.game.level - 1]) {
            this.game.collectionScores[this.game.level - 1] = this.game.totalScore;
            Game.persistence.saveHighscores(this.game.collectionScores);
        }
        this.game.whichScore++;
    }
}

const game = new Game()
game.init(500, 850)
game.startLoop()

const w = cs.window.create('PaddleBall', game.width, game.height)

w.onResize(e => {
    game.initSize(e.width, e.height)
})

w.onUpdate(g => {
    if (!game.done) {
        const deltaMs = w.getLastFrameDuration() / 1000
        game.update(deltaMs)
    }
    game.render(g)
})

// w.onFocus(() => {
//     Game.startLoop()
// })

// w.onLoseFocus(() => {
//     Game.stop();
// })

// $('#canvas').bind('touchend', this.onHandTouchEnd)
// $('#canvas').bind('touchmove', this.onHandTouchMove)

w.onMouseUp(e => {
    if (!game.done) {
        if (e.clicks == 1) {
            game.onMouseClick(e.x, e.y)
        }
    }
})

w.onMouseMove(e => {
    if (!game.done) {
        game.onMouseMove(e.x, e.y)
    }
})

Game.persistence.saveSettings(true)

function circleToAABB(cx, cy, cr, x1, y1, x2, y2) {
	const bx = Math.min(Math.max(x1, cx), x2)
    const by = Math.min(Math.max(y1, cy), y2)
	const cb_x = cx - bx
    const cb_y = cy - by
    const d = cb_x * cb_x + cb_y * cb_y
	return d < cr * cr
}