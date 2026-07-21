import re

from gitlint.rules import CommitMessageBody, CommitMessageTitle, CommitRule, LineRule, RuleViolation
from gitlint.options import ListOption

EMOJI_PATTERN = re.compile(
    "[\U0001f1e6-\U0001f1ff\U0001f300-\U0001f9ff\U0001fa00-\U0001faff"
    "\u2600-\u26ff\u2700-\u27bf\u2b00-\u2bff\ufe0f\u20e3]"
)


# Issue-tracker tags: JIRA-style "#PROJ-1704" and GitHub-style "#1704".
TICKET_TAG_PATTERN = re.compile(r"#[A-Za-z0-9]+-[0-9]+|#[0-9]+")


BANNED_PREFIXES = {"fix", "fixup", "wip", "tmp"}


class NoBannedPrefix(LineRule):
    """Reject commits using a banned word as the module prefix."""

    name = "no-banned-prefix"
    id = "UC3"
    target = CommitMessageTitle

    def validate(self, line, _commit):
        if ":" not in line:
            return
        for prefix in line.split(":")[:-1]:
            prefix = prefix.strip().lower()
            if prefix in BANNED_PREFIXES:
                return [RuleViolation(
                    self.id,
                    f"module prefix '{prefix}' is not allowed, use a proper module name",
                )]


class NoTicketTagInTitle(LineRule):
    """Reject issue-tracker tags in the title; keep them in the body."""

    name = "no-ticket-tag-in-title"
    id = "UC4"
    target = CommitMessageTitle

    def validate(self, line, _commit):
        match = TICKET_TAG_PATTERN.search(line)
        if match:
            return [RuleViolation(
                self.id,
                f"title must not contain the ticket tag '{match.group()}', "
                "put it in the body instead",
            )]


class BodyBulletFormat(LineRule):
    """Body lines must be blank, start with '- ', or be indented continuation."""

    name = "body-bullet-format"
    id = "UC1"
    target = CommitMessageBody

    def validate(self, line, _commit):
        if not line:
            return
        if line.startswith("- ") or line.startswith("  "):
            return
        return [RuleViolation(
            self.id,
            f"body line must be blank, bullet '- ', or indented continuation: {line}",
        )]


class NoBannedContent(CommitRule):
    """Reject signature trailers and emojis in commit messages."""

    name = "no-banned-content"
    id = "UC2"
    options_spec = [
        ListOption("banned", ["Co-Authored-By", "Signed-off-by"], "Banned phrases in body"),
    ]

    def validate(self, commit):
        violations = []

        for phrase in self.options["banned"].value:
            for i, line in enumerate(commit.message.body, start=2):
                if phrase.lower() in line.lower():
                    violations.append(RuleViolation(
                        self.id, f"body must not contain '{phrase}'",
                        line, line_nr=i,
                    ))

        full = commit.message.original
        if EMOJI_PATTERN.search(full):
            violations.append(RuleViolation(
                self.id, "commit message must not contain emojis",
            ))

        return violations or None
