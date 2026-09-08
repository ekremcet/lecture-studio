import Foundation

/// Scaffolds that follow the conventions of the existing courses. Mirrors app/lib/server/templates.ts
/// line for line, so a deck created on the Mac matches one created in the web app.
public enum Templates {
    public static func contactLines(_ p: Profile) -> [String] {
        var lines: [String] = []
        if let e = p.email, !e.isEmpty { lines.append("- **Email:** \(e)") }
        let rx = Rx("^([^:]{2,40}):\\s*(.+)$")
        for c in p.contact ?? [] {
            if let m = rx.first(c) { lines.append("- **\((m[1] ?? "").trimmed):** \((m[2] ?? "").trimmed)") } else { lines.append("- \(c)") }
        }
        return lines
    }

    static func contactBlock(_ p: Profile, heading: String = "## Contact") -> String {
        let lines = contactLines(p)
        return lines.isEmpty ? "" : "\(heading)\n\n\(lines.joined(separator: "\n"))\n\n"
    }

    public static let LECTURE_STYLE_BLOCK = """
    style: |
      section {
        font-size: 20px;
        padding: 32px;
        justify-content: flex-start;
        text-align: left;
      }
      section h1 {
        font-size: 36px;
        margin-bottom: 20px;
        margin-top: 0;
        text-align: left;
      }
      section h2 {
        font-size: 30px;
        margin-bottom: 15px;
        margin-top: 20px;
        text-align: left;
      }
      section h3 {
        font-size: 24px;
        margin-bottom: 10px;
        text-align: left;
      }
      section ul, section ol {
        margin: 10px 0;
        text-align: left;
      }
      section li {
        margin: 8px 0;
        line-height: 1.3;
        text-align: left;
      }
      section blockquote {
        margin: 15px 0;
        text-align: left;
      }
      section pre {
        text-align: left;
      }
      section small {
        font-size: 12px;
        font-style: italic;
      }
      section p {
        text-align: left;
      }
      .two-columns {
        display: flex;
        gap: 24px;
      }
      .column {
        flex: 1;
      }
    """

    public static let TALK_STYLE_BLOCK = """
    style: |
      section {
        font-size: 22px;
        padding: 32px;
        text-align: left;
      }
      section h1 {
        font-size: 42px;
        margin-bottom: 20px;
      }
      section h2 {
        font-size: 32px;
        margin-bottom: 15px;
      }
      section h3 {
        font-size: 26px;
        margin-bottom: 10px;
      }
      .two-columns {
        display: flex;
        gap: 24px;
      }
      .column {
        flex: 1;
      }
    """

    public struct DeckInput {
        public var code: String
        public var courseName: String
        public var week: Int
        public var topic: String
        public var date: String?
        public var math: Bool = false
        public var boldWeekFooter: Bool = false
        public var previousTopic: String?
        public var profile: Profile
        public var unitLabel: String?
        public init(code: String, courseName: String, week: Int, topic: String, date: String? = nil, math: Bool = false, boldWeekFooter: Bool = false, previousTopic: String? = nil, profile: Profile, unitLabel: String? = nil) {
            self.code = code; self.courseName = courseName; self.week = week; self.topic = topic; self.date = date; self.math = math
            self.boldWeekFooter = boldWeekFooter; self.previousTopic = previousTopic; self.profile = profile; self.unitLabel = unitLabel
        }
    }

    public static func fmtDate(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: d)
    }

    public static func deck(_ i: DeckInput) -> String {
        let word = (i.unitLabel ?? "").isEmpty ? "week" : i.unitLabel!
        let U = word.capFirst
        let p = i.profile
        let footer = i.boldWeekFooter ? "\"**\(U) \(i.week)**: \(i.topic)\"" : "\"\(U) \(i.week): \(i.topic)\""
        let recap = i.week > 1 ? """
        ---

        # Recap: \(U) \(i.week - 1)

        ## What We Covered

        - \(i.previousTopic ?? "Topic 1")
        - Topic 2
        - Topic 3

        ## Today's Focus

        One sentence on what this \(word) adds.


        """ : ""
        let presenter = p.name.isEmpty ? "" : "**Instructor:** \(p.name)\n"
        let header = "\(i.code.isEmpty ? "" : "\(i.code) - ")\(i.courseName)"
        let sub = i.code.isEmpty ? "" : "## \(i.courseName)\n\n"
        return """
        ---
        marp: true
        \(i.math ? "math: mathjax\n" : "")paginate: true
        size: 16:9
        header: "\(header)"
        footer: \(footer)
        \(LECTURE_STYLE_BLOCK)
        ---

        # \(i.code.isEmpty ? i.courseName : i.code)

        \(sub)### \(U) \(i.week): \(i.topic)

        \(presenter)**Date:** \(i.date ?? fmtDate())

        \(recap)---

        # Today's Agenda

        **Part 1: First topic**

        - Subtopic
        - Subtopic

        **Part 2: Second topic**

        - Subtopic
        - Subtopic

        ---

        # First Concept

        <div class="two-columns">
        <div class="column">

        ### What it is

        - Point 1
        - Point 2
        - Point 3

        </div>
        <div class="column">

        ### Why it matters

        - Point A
        - Point B

        </div>
        </div>

        ---

        # Summary

        ## Key Takeaways

        1. **Point one**
        2. **Point two**
        3. **Point three**

        ---

        # Next \(U) Preview

        ## \(U) \(i.week + 1): Next topic

        We'll explore:

        - Topic 1
        - Topic 2

        ## Reading Assignment

        - Chapter X from the textbook

        ---

        # Thank You!

        \(contactBlock(p, heading: "## Contact Information"))## Next Class

        - **Date:** DD.MM.YYYY
        - **Topic:** Next topic

        """
    }

    public struct TalkInput {
        public var title: String
        public var event: String?
        public var date: String?
        public var profile: Profile
        public init(title: String, event: String? = nil, date: String? = nil, profile: Profile) {
            self.title = title; self.event = event; self.date = date; self.profile = profile
        }
    }

    public static func talk(_ i: TalkInput) -> String {
        let p = i.profile
        let who = [p.name, p.affiliation ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        let footer = [i.title, i.event ?? ""].filter { !$0.isEmpty }.joined(separator: " - ")
        let event = (i.event ?? "").isEmpty ? "" : "### \(i.event!)\n\n"
        let whoLine = who.isEmpty ? "" : "**\(who)**\n"
        return """
        ---
        marp: true
        theme: default
        paginate: true
        size: 16:9
        header: "\(i.title)"
        footer: "\(footer)"
        \(TALK_STYLE_BLOCK)
        ---

        <!-- _paginate: false -->
        <!-- _header: "" -->
        <!-- _footer: "" -->

        # \(i.title)

        \(event)\(whoLine)**\(i.date ?? fmtDate())**

        ---

        # Agenda

        1. Why this matters
        2. The core idea
        3. What it looks like in practice
        4. Takeaways

        ---

        # Why This Matters

        - The problem, in one sentence
        - Who has it, and what it costs them
        - What changes when it is solved

        ---

        # The Core Idea

        <div class="two-columns">
        <div class="column">

        ### Before

        - How it was done
        - What went wrong

        </div>
        <div class="column">

        ### After

        - What the idea changes
        - What it costs

        </div>
        </div>

        ---

        # Takeaways

        1. **One thing to remember**
        2. **One thing to try**
        3. **One thing to read**

        ---

        <!-- _paginate: false -->

        # Thank You

        \(contactBlock(p))
        """
    }

    public static func guide(week: Int, topic: String, unitLabel: String = "week") -> String {
        """
        # \(unitLabel.capFirst) \(week) Instructor Guide — \(topic)

        ## Six 20-Minute Blocks

        | Block | Core path | Student output |
        |---|---|---|
        | 1 | Concepts A and B (slides x-y) | Output 1 |
        | 2 | Concepts C and D (slides x-y) | Output 2 |
        | 3 | Worked example E (slides x-y) | Output 3 |
        | 4 | Practice F (slides x-y) | Output 4 |
        | 5 | Concepts G and H (slides x-y) | Output 5 |
        | 6 | Studio tied to the project or lab (slides x-y) | Artifact usable in the deliverable |

        ## Facilitation Notes

        - Framing note (constraints, no universally best answer).
        - Artifact rule (what every student output must contain).
        - Project or lab link (how block 6 feeds the deliverable).

        ## Minimum Viable Path

        Concept A → Concept C → Practice F → Studio.

        ## Extension

        One task that makes students defend, review, test, or revise their own artifact.

        """
    }

    public struct LectureInput {
        public var code: String
        public var name: String
        public var language: String
        public var semester: String
        public var ects: Int?
        public var localCredit: Int?
        public var profile: Profile
        public var unitLabel: String?
        public init(code: String, name: String, language: String, semester: String, ects: Int? = nil, localCredit: Int? = nil, profile: Profile, unitLabel: String? = nil) {
            self.code = code; self.name = name; self.language = language; self.semester = semester; self.ects = ects; self.localCredit = localCredit; self.profile = profile; self.unitLabel = unitLabel
        }
    }

    public static func syllabus(_ i: LectureInput) -> String {
        let U = ((i.unitLabel ?? "").isEmpty ? "week" : i.unitLabel!).capFirst
        let code = i.code.isEmpty ? "" : "- **Code:** \(i.code)\n"
        let unit = (i.profile.unit ?? "").isEmpty ? "" : "- **Owner Academic Unit:** \(i.profile.unit!)\n"
        let coord = i.profile.name.isEmpty ? "" : "- **Course Coordinator:** \(i.profile.name)\n- **Instructor(s):** \(i.profile.name)\n"
        let policies = (i.profile.style ?? "").isEmpty
            ? "- Describe the exam, attendance, and AI-use policies of the course."
            : i.profile.style!.components(separatedBy: CharacterSet.newlines).filter { !$0.isEmpty }.map { "- \($0.trimmed)" }.joined(separator: "\n")
        return """
        # Course Information Form

        ## Basic Information

        - **Title:** \(i.name)
        \(code)- **Local Credit:** \(i.localCredit ?? 3)
        - **ECTS:** \(i.ects ?? 6)
        - **Lecture (hour/week):** 3
        - **Practical (hour/week):** 0
        - **Laboratory (hour/week):** 0

        ## Course Details

        - **Prerequisite:** None
        - **Semester:** \(i.semester)
        - **Course Language:** \(i.language)
        - **Level Of Course:** First Cycle
        - **Course Category:** Core Course
        - **Mode Of Delivery:** Face-to-Face
        \(unit)\(coord)- **Assistant(s):** Not specified

        ## Course Objectives

        Write two or three sentences on what the course is for.

        ## Course Content

        List the topics of the semester in one paragraph.

        ## Course Learning Outcomes

        By the end of the course, students will be able to:

        1. Outcome one.
        2. Outcome two.
        3. Outcome three.

        ## \(i.semester) \(U)ly Subjects

        | \(U) | Subject | Reading |
        |---|---|---|
        | 1 | Introduction | |
        | 2 | | |
        | 3 | | |
        | 4 | | |
        | 5 | | |
        | 6 | | |
        | 7 | | |
        | 8 | Midterm | |
        | 9 | | |
        | 10 | | |
        | 11 | | |
        | 12 | | |
        | 13 | | |
        | 14 | Review | |

        ## Evaluation System

        | Component | Weight |
        |---|---|
        | In-term work | 60% |
        | Final exam | 40% |

        ## Recommended References

        - Textbook

        ## Course Policies

        \(policies)

        """
    }

    public static func courseContext(_ i: LectureInput, folder: String) -> String {
        let u = (i.unitLabel ?? "").isEmpty ? "week" : i.unitLabel!
        let place = [i.profile.affiliation ?? "", i.profile.unit ?? ""].filter { !$0.isEmpty }
        let at = place.isEmpty ? "" : " at \(place.joined(separator: ", "))"
        let code = i.code.isEmpty ? "" : "\(i.code) - "
        let style = (i.profile.style ?? "").isEmpty ? "Describe how this course is taught: pacing, exam policy, tone, what to avoid." : i.profile.style!
        return """
        # AGENTS.md

        This is the course repository for **\(code)\(i.name)**\(at).

        ## Project Structure

        - `\(u){N}/` - Materials of one \(u) (`\(u){N}-slides.md`, exported PDF, `assets/`, `sources/`)
        - `sources/` - Readings and notes for the whole course, indexed for the agent
        - `syllabus.md` - Course syllabus

        ## Course Content

        **Semester:** \(i.semester)
        **Language:** \(i.language)

        Fill in the week-by-week topics once the syllabus is final.

        ## Slides Format (Marp)

        Every deck starts with the shared front matter (see any `\(u){N}-slides.md` in `\(folder)`):
        `header: "\(code)\(i.name)"`, `footer: "\(u.capFirst) N: Topic Title"`, 16:9, paginate, and the house style block.

        Slide patterns: title slide, recap, agenda, two-column concept slides, good/bad code pairs, background images from `assets/`,
        summary, next-week preview, thank-you slide with contact information.

        ## Teaching Style

        \(style)

        """
    }
}
