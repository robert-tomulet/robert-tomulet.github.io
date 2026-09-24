cat > /var/www/acesrobotics.dev/html/app/routes/admin.py << 'EOF'
from functools import wraps
from flask import Blueprint, render_template, redirect, url_for, flash, request, current_app, jsonify
from flask_login import login_user, logout_user, login_required, current_user
from app import db, limiter, csrf
from app.models import User, Article, Category, Image
from app.forms import LoginForm, UserForm, ArticleForm
from app.utils import sanitize_html, unique_slug, save_upload, parse_categories
import os

bp = Blueprint('admin', __name__, url_prefix='/admin')


def admin_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not current_user.is_authenticated or not current_user.is_admin():
            flash('Nu ai permisiunea să accesezi această pagină.', 'danger')
            return redirect(url_for('admin.login'))
        return f(*args, **kwargs)
    return decorated_function


@bp.route('/')
def index():
    if current_user.is_authenticated:
        return redirect(url_for('admin.dashboard'))
    return redirect(url_for('admin.login'))


@bp.route('/login', methods=['GET', 'POST'])
@limiter.limit("5 per minute")
def login():
    if current_user.is_authenticated:
        return redirect(url_for('admin.dashboard'))
    form = LoginForm()
    if form.validate_on_submit():
        user = User.query.filter_by(username=form.username.data).first()
        if user and user.check_password(form.password.data):
            login_user(user, remember=False)
            next_page = request.args.get('next')
            if next_page:
                return redirect(next_page)
            return redirect(url_for('admin.dashboard'))
        flash('Utilizator sau parolă incorectă.', 'danger')
    return render_template('admin/login.html', form=form)


@bp.route('/logout')
@login_required
def logout():
    logout_user()
    flash('Te-ai deconectat cu succes.', 'success')
    return redirect(url_for('admin.login'))


@bp.route('/dashboard')
@login_required
def dashboard():
    if current_user.is_admin():
        articles = Article.query.order_by(Article.event_date.desc()).all()
    else:
        articles = Article.query.filter_by(author_id=current_user.id).order_by(Article.event_date.desc()).all()
    return render_template('admin/dashboard.html', articles=articles)


@bp.route('/users')
@login_required
@admin_required
def users():
    users = User.query.order_by(User.created_at.desc()).all()
    return render_template('admin/users.html', users=users)


@bp.route('/users/new', methods=['GET', 'POST'])
@login_required
@admin_required
def new_user():
    form = UserForm()
    if form.validate_on_submit():
        user = User(username=form.username.data, role='writer')
        user.set_password(form.password.data)
        db.session.add(user)
        db.session.commit()
        flash(f'Contul pentru {user.username} a fost creat.', 'success')
        return redirect(url_for('admin.users'))
    return render_template('admin/user_form.html', form=form)


@bp.route('/users/<int:id>/delete', methods=['POST'])
@login_required
@admin_required
def delete_user(id):
    user = User.query.get_or_404(id)
    if user.is_admin():
        flash('Nu poți șterge contul de admin.', 'danger')
        return redirect(url_for('admin.users'))
    db.session.delete(user)
    db.session.commit()
    flash('Contul a fost șters.', 'success')
    return redirect(url_for('admin.users'))


@bp.route('/articles/new', methods=['GET', 'POST'])
@login_required
def new_article():
    form = ArticleForm()
    if form.validate_on_submit():
        article = Article(
            title=form.title.data,
            slug=unique_slug(Article, form.title.data),
            content=sanitize_html(form.content.data),
            event_date=form.event_date.data,
            author_id=current_user.id
        )
        article.categories = parse_categories(form.categories.data)
        db.session.add(article)
        db.session.commit()
        flash('Articolul a fost creat.', 'success')
        return redirect(url_for('admin.dashboard'))
    return render_template('admin/article_form.html', form=form, article=None)


@bp.route('/articles/<int:id>/edit', methods=['GET', 'POST'])
@login_required
def edit_article(id):
    article = Article.query.get_or_404(id)
    if not current_user.is_admin() and article.author_id != current_user.id:
        flash('Nu poți edita acest articol.', 'danger')
        return redirect(url_for('admin.dashboard'))
    form = ArticleForm(obj=article)
    if request.method == 'GET':
        form.categories.data = ', '.join([c.name for c in article.categories])
    if form.validate_on_submit():
        article.title = form.title.data
        article.slug = unique_slug(Article, form.title.data, existing_id=article.id)
        article.content = sanitize_html(form.content.data)
        article.event_date = form.event_date.data
        article.categories = parse_categories(form.categories.data)
        db.session.commit()
        flash('Articolul a fost actualizat.', 'success')
        return redirect(url_for('admin.dashboard'))
    return render_template('admin/article_form.html', form=form, article=article)


@bp.route('/articles/<int:id>/delete', methods=['POST'])
@login_required
def delete_article(id):
    article = Article.query.get_or_404(id)
    if not current_user.is_admin() and article.author_id != current_user.id:
        flash('Nu poți șterge acest articol.', 'danger')
        return redirect(url_for('admin.dashboard'))
    for img in article.images:
        path = os.path.join(current_app.config['UPLOAD_FOLDER'], img.filename)
        if os.path.exists(path):
            os.remove(path)
    db.session.delete(article)
    db.session.commit()
    flash('Articolul a fost șters.', 'success')
    return redirect(url_for('admin.dashboard'))


@bp.route('/upload-image', methods=['POST'])
@login_required
@csrf.exempt
def upload_image():
    if 'file' not in request.files:
        return jsonify({'error': 'Niciun fișier încărcat.'}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'Niciun fișier selectat.'}), 400
    filename, error = save_upload(file)
    if error:
        return jsonify({'error': error}), 400
    image = Image(filename=filename, original_name=file.filename)
    db.session.add(image)
    db.session.commit()
    location = url_for('public.uploaded_file', filename=filename, _external=False)
    return jsonify({'location': location})
EOF

systemctl restart aces-cms
