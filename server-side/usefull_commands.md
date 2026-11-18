Commands for cmd:

run server: python manage.py runserver
drops all tables: python manage.py flush
create admin user: python manage.py createsuperuser
    name: admin
    email: admin@admin.com
create migrations: python manage.py makemigrations
migrate: python manage.py migrate

Commands for git:

pull: git pull
new branch: git checkout -b new-branch-name
push: git push -u origin new-branch-name