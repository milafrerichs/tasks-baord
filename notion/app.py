import os
from flask import Flask, escape, request
from notion.client import NotionClient
from notion.block import TextBlock

NOTION_TOKEN = os.environ['NOTION_TOKEN']
NOTION_MOOD_BOARD = os.environ['NOTION_MOOD_BOARD']

app = Flask(__name__)

@app.route('/mood/<mood>', methods=['GET', 'POST'])
def mood(mood):
    n = Notion(NOTION_MOOD_BOARD)
    if request.method == 'POST':
        new_item = n.add_row(mood, "")
        return { "mood": mood, "notion_id": new_item.id }
    return { "mood": mood }

class Notion:
    def __init__(self, page_id):
        self.client = NotionClient(token_v2=NOTION_TOKEN)
        self.page = self.client.get_block(page_id)

    def add_row(self, title, content):
        collection = self.page.collection
        # don't delete the next line, it is a hack to work with databases
        print(collection.parent.views)
        row = collection.add_row()
        row.title = title
        row_content = row.children.add_new(
            TextBlock, title=content
        )
        return row
