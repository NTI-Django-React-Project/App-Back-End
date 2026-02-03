from setuptools import setup, find_packages
import os

# Read version from environment or use default
VERSION = os.getenv('BUILD_NUMBER', '0.0.1')

# Read long description from README
with open('README.md', 'r', encoding='utf-8') as f:
    long_description = f.read()

setup(
    name='django-backend-app',
    version=VERSION,
    author='Your Team',
    author_email='team@example.com',
    description='Django Backend Application',
    long_description=long_description,
    long_description_content_type='text/markdown',
    url='https://github.com/your-org/django-backend',
    packages=find_packages(exclude=['tests*', 'docs*']),
    classifiers=[
        'Development Status :: 4 - Beta',
        'Intended Audience :: Developers',
        'Topic :: Software Development :: Libraries :: Python Modules',
        'License :: OSI Approved :: MIT License',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.11',
        'Framework :: Django',
        'Framework :: Django :: 4.2',
    ],
    python_requires='>=3.11',
    install_requires=[
        'Django>=4.2.0',
        'djangorestframework>=3.14.0',
        'psycopg2-binary>=2.9.0',
        'gunicorn>=21.2.0',
        'python-decouple>=3.8',
        'django-cors-headers>=4.3.0',
        'boto3>=1.34.0',
    ],
    extras_require={
        'dev': [
            'pytest>=7.4.0',
            'pytest-django>=4.7.0',
            'pytest-cov>=4.1.0',
            'black>=23.12.0',
            'flake8>=7.0.0',
        ],
    },
    include_package_data=True,
    zip_safe=False,
)
